from typing import List, Optional
import pandas as pd

from app.strategies.models import (
    ActionSignal,
    BotConfigModel,
    MarketRegime,
    PortfolioState,
    SignalType,
    TrancheModel,
    TrancheStatus,
)
from app.strategies.regime import MarketRegimeDetector


class BtcQuantumEvolutionRegimeStrategy:
    """Flagship Quantum Evolution Strategy."""

    def __init__(
        self,
        config: BotConfigModel,
        enable_compounding: bool = True,
        macro_indicator: str = "ema_daily_200",
        trailing_stop_pct: Optional[float] = None,
        panic_rsi_threshold: float = 28.0,
        trend_weight: Optional[float] = None,
        t0_rsi_threshold: float = 48.0,
        base_max_tranches: int = 5,
        extra_floor_tranches: int = 3,
        floor_t5_weight: float = 0.40,
        floor_tranche_weights: Optional[List[float]] = None,
        trend_highest_price: Optional[float] = None,
    ):
        self.config = config
        self.enable_compounding = enable_compounding
        self.macro_indicator = macro_indicator
        self.trend_weight = trend_weight if trend_weight is not None else config.trend_weight
        self.trailing_stop_pct = trailing_stop_pct if trailing_stop_pct is not None else config.trailing_stop_pct
        self.t0_rsi_threshold = t0_rsi_threshold
        self.panic_rsi_threshold = panic_rsi_threshold
        self.base_max_tranches = base_max_tranches
        self.extra_floor_tranches = extra_floor_tranches
        self.max_total_tranches = self.base_max_tranches + self.extra_floor_tranches
        self.floor_t5_weight = floor_t5_weight
        self.floor_tranche_weights = floor_tranche_weights or [0.40, 0.35, 0.25]
        self.trend_highest_price: Optional[float] = trend_highest_price

    def evaluate(self, current_row: pd.Series, portfolio: PortfolioState) -> List[ActionSignal]:
        signals: List[ActionSignal] = []
        regime = MarketRegimeDetector.detect_regime(current_row)

        close_price = float(current_row["close"])
        high_price = float(current_row["high"])
        low_price = float(current_row["low"])
        atr_14 = float(current_row.get("atr_14", close_price * 0.02))
        rsi = float(current_row.get("rsi_14", 50.0))

        active_tranches = portfolio.active_tranches

        # 1. EXITS
        for tranche in list(active_tranches):
            if tranche.status != TrancheStatus.ACTIVE:
                continue

            # Standard or subsidized Take Profit
            if high_price >= tranche.target_sell_price:
                signals.append(
                    ActionSignal(
                        signal_type=SignalType.SELL_TRANCHE,
                        symbol=self.config.symbol,
                        tranche_index=tranche.tranche_index,
                        price=tranche.target_sell_price,
                        amount=tranche.amount,
                        allocated_usdt=tranche.allocated_budget,
                        reason=f"Take Profit hit ({tranche.target_sell_price:.2f}) [T{tranche.tranche_index}]",
                        tranche_ref=tranche,
                    )
                )
                continue

            # Trailing Stop in strong bull trend
            if regime == MarketRegime.BULL_TREND and self.trend_highest_price is not None:
                if high_price > self.trend_highest_price:
                    self.trend_highest_price = high_price

                stop_price = self.trend_highest_price * (1.0 - self.trailing_stop_pct / 100.0)
                if tranche.buy_price and stop_price > tranche.buy_price:
                    if low_price <= stop_price:
                        signals.append(
                            ActionSignal(
                                signal_type=SignalType.SELL_TRANCHE,
                                symbol=self.config.symbol,
                                tranche_index=tranche.tranche_index,
                                price=stop_price,
                                amount=tranche.amount,
                                allocated_usdt=tranche.allocated_budget,
                                reason=f"Trailing Stop hit (+{((stop_price/tranche.buy_price)-1)*100:.1f}%) [T{tranche.tranche_index}]",
                                tranche_ref=tranche,
                            )
                        )
                        self.trend_highest_price = None

        if signals:
            return signals

        # 2. CAPITAL BASE
        if self.enable_compounding:
            effective_base = (
                self.config.budget
                + max(0.0, portfolio.total_realized_profit)
                + portfolio.total_deposited_amount
                - portfolio.total_withdrawn_amount
            )
        else:
            effective_base = self.config.budget

        occupied_base = {
            t.tranche_index: t
            for t in active_tranches
            if t.status == TrancheStatus.ACTIVE and t.tranche_index < self.base_max_tranches
        }
        occupied_floor = {
            t.tranche_index: t
            for t in active_tranches
            if t.status == TrancheStatus.ACTIVE and t.tranche_index >= self.base_max_tranches
        }

        max_idx_base = max(occupied_base.keys()) if occupied_base else -1
        base_exhausted = max_idx_base >= self.base_max_tranches - 1

        # 3. ENTRIES
        if not base_exhausted:
            if regime == MarketRegime.RANGE:
                if len(occupied_base) == 0:
                    macro_val = float(current_row.get(self.macro_indicator, current_row.get("ema_200", 0.0)))
                    if close_price >= macro_val and rsi < self.t0_rsi_threshold:
                        budget_t0 = effective_base * self.config.tranche_weights[0]
                        real_budget = min(budget_t0, portfolio.available_usdt)
                        if real_budget >= 10.0:
                            signals.append(
                                ActionSignal(
                                    signal_type=SignalType.BUY_TRANCHE,
                                    symbol=self.config.symbol,
                                    tranche_index=0,
                                    price=close_price,
                                    amount=real_budget / close_price,
                                    allocated_usdt=real_budget,
                                    target_sell_price=close_price * (1.0 + self.config.take_profit_pct / 100.0),
                                    reason="RANGE T0",
                                )
                            )
                else:
                    max_idx = max(occupied_base.keys())
                    next_idx = max_idx + 1
                    if next_idx < self.base_max_tranches:
                        last_buy_price = occupied_base[max_idx].buy_price
                        atr_multipliers = [2.0, 3.5, 5.5, 8.0]
                        mult = atr_multipliers[min(next_idx - 1, len(atr_multipliers) - 1)]
                        drop_required = atr_14 * mult
                        if close_price <= (last_buy_price - drop_required):
                            w_idx = min(next_idx, len(self.config.tranche_weights) - 1)
                            budget_t = effective_base * self.config.tranche_weights[w_idx]
                            real_budget = min(budget_t, portfolio.available_usdt)
                            if real_budget >= 10.0:
                                signals.append(
                                    ActionSignal(
                                        signal_type=SignalType.BUY_TRANCHE,
                                        symbol=self.config.symbol,
                                        tranche_index=next_idx,
                                        price=close_price,
                                        amount=real_budget / close_price,
                                        allocated_usdt=real_budget,
                                        target_sell_price=close_price * (1.0 + self.config.take_profit_pct / 100.0),
                                        reason=f"RANGE T{next_idx}",
                                    )
                                )

            elif regime == MarketRegime.BULL_TREND:
                if len(occupied_base) == 0:
                    ema_50 = float(current_row.get("ema_50", close_price))
                    if close_price <= ema_50 * 1.015 or rsi < 55.0:
                        budget_trend = effective_base * self.trend_weight
                        real_budget = min(budget_trend, portfolio.available_usdt)
                        if real_budget >= 10.0:
                            self.trend_highest_price = high_price
                            signals.append(
                                ActionSignal(
                                    signal_type=SignalType.BUY_TRANCHE,
                                    symbol=self.config.symbol,
                                    tranche_index=0,
                                    price=close_price,
                                    amount=real_budget / close_price,
                                    allocated_usdt=real_budget,
                                    target_sell_price=close_price * 2.0,
                                    reason=f"BULL TREND ENTRY: Trend Following {self.trend_weight*100:.0f}%",
                                )
                            )

            elif regime == MarketRegime.PANIC_CAPITULATION:
                if len(occupied_base) == 0 and rsi < self.panic_rsi_threshold:
                    budget_panic = effective_base * 0.35
                    real_budget = min(budget_panic, portfolio.available_usdt)
                    if real_budget >= 10.0:
                        signals.append(
                            ActionSignal(
                                signal_type=SignalType.BUY_TRANCHE,
                                symbol=self.config.symbol,
                                tranche_index=0,
                                price=close_price,
                                amount=real_budget / close_price,
                                allocated_usdt=real_budget,
                                target_sell_price=close_price * 1.07,
                                reason="PANICO",
                            )
                        )

            if signals:
                return signals

        # 4. FLOOR MODE (when base tranches are fully exhausted and liquid cash >= $25)
        if base_exhausted and portfolio.available_usdt >= 25.0:
            if regime == MarketRegime.PANIC_CAPITULATION and rsi < self.panic_rsi_threshold:
                if len(occupied_floor) == 0:
                    sniper_budget = min(portfolio.available_usdt * 0.40, portfolio.available_usdt)
                    if sniper_budget >= 10.0:
                        signals.append(
                            ActionSignal(
                                signal_type=SignalType.BUY_TRANCHE,
                                symbol=self.config.symbol,
                                tranche_index=self.base_max_tranches,
                                price=close_price,
                                amount=sniper_budget / close_price,
                                allocated_usdt=sniper_budget,
                                target_sell_price=close_price * 1.07,
                                reason="SUELO PANICO",
                            )
                        )
                        return signals

            if len(occupied_floor) < self.extra_floor_tranches:
                if len(occupied_floor) == 0:
                    lowest_base_buy = min(t.buy_price for t in occupied_base.values())
                    if close_price <= (lowest_base_buy - atr_14 * 1.5) and rsi < 48.0:
                        idx_floor = self.base_max_tranches
                        weight = self.floor_tranche_weights[0] if self.floor_tranche_weights else self.floor_t5_weight
                        floor_budget = min(portfolio.available_usdt * weight, portfolio.available_usdt)
                        if floor_budget >= 10.0:
                            signals.append(
                                ActionSignal(
                                    signal_type=SignalType.BUY_TRANCHE,
                                    symbol=self.config.symbol,
                                    tranche_index=idx_floor,
                                    price=close_price,
                                    amount=floor_budget / close_price,
                                    allocated_usdt=floor_budget,
                                    target_sell_price=close_price * (1.0 + self.config.take_profit_pct / 100.0),
                                    reason=(
                                        f"AUTO FLOOR T{idx_floor}: SUELO EVOLUTION ({close_price:.2f} <= {lowest_base_buy - atr_14 * 1.5:.2f}, RSI {rsi:.1f})"
                                    ),
                                )
                            )
                else:
                    max_idx_floor = max(occupied_floor.keys())
                    next_floor = max_idx_floor + 1
                    if next_floor < self.max_total_tranches:
                        last_floor_price = occupied_floor[max_idx_floor].buy_price
                        floor_drop = atr_14 * 2.0
                        if close_price <= (last_floor_price - floor_drop):
                            idx_rel = next_floor - self.base_max_tranches
                            weight = self.floor_tranche_weights[min(idx_rel, len(self.floor_tranche_weights) - 1)]
                            floor_budget = min(portfolio.available_usdt * weight, portfolio.available_usdt)
                            if floor_budget >= 10.0:
                                signals.append(
                                    ActionSignal(
                                        signal_type=SignalType.BUY_TRANCHE,
                                        symbol=self.config.symbol,
                                        tranche_index=next_floor,
                                        price=close_price,
                                        amount=floor_budget / close_price,
                                        allocated_usdt=floor_budget,
                                        target_sell_price=close_price * (1.0 + self.config.take_profit_pct / 100.0),
                                        reason=(
                                            f"AUTO FLOOR T{next_floor}: SUELO EVOLUTION ({close_price:.2f} <= {last_floor_price - floor_drop:.2f})"
                                        ),
                                    )
                                )

        return signals
