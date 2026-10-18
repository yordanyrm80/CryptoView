from typing import List, Optional
import pandas as pd
from src.core.regime_detector import MarketRegimeDetector
from src.domain.models import BotConfig, MarketRegime, Tranche, TrancheStatus
from src.strategies.base import ActionSignal, BaseStrategy, PortfolioState, SignalType


class BtcQuantumCompoundRegimeStrategy(BaseStrategy):
    """Quantitative Quantum Strategy for Bitcoin (BTC/USDT).

    Optimized Architecture:
    - Front-Loaded Weights [0.30, 0.25, 0.20, 0.15, 0.10].
    - High Precision Trailing Stop (2.0% default) in strong bull trends.
    - Macro Multi-Timeframe Filter (Daily EMA 200 / 4,800h).
    - Volatility Chained Dynamic Spacing (Chained ATR: 2.0x, 3.5x, 5.5x, 8.0x).
    - Calibrated Panic Sniper (RSI < 28.0).
    """

    def __init__(
        self,
        config: BotConfig,
        enable_compounding: bool = True,
        macro_indicator: str = "ema_daily_200",
        trailing_stop_pct: Optional[float] = None,
        panic_rsi_threshold: float = 28.0,
        trend_weight: Optional[float] = None,
        t0_rsi_threshold: float = 48.0,
    ):
        super().__init__(config)
        self.enable_compounding = enable_compounding
        self.macro_indicator = macro_indicator
        self.trailing_stop_pct = (
            trailing_stop_pct if trailing_stop_pct is not None else config.trailing_stop_pct
        )
        self.panic_rsi_threshold = panic_rsi_threshold
        self.trend_weight = (
            trend_weight if trend_weight is not None else getattr(config, "trend_weight", 0.40)
        )
        self.t0_rsi_threshold = t0_rsi_threshold

        self.trend_highest_price: Optional[float] = None
        self.trend_entry_price: Optional[float] = None

    def evaluate(self, current_row: pd.Series, portfolio: PortfolioState) -> List[ActionSignal]:
        signals: List[ActionSignal] = []
        regime = MarketRegimeDetector.detect_regime(current_row)

        close_price = current_row["close"]
        high_price = current_row["high"]
        low_price = current_row["low"]
        atr_14 = current_row.get("atr_14", close_price * 0.02)
        rsi = current_row.get("rsi_14", 50.0)

        active_tranches = portfolio.active_tranches

        # 1. EXIT EVALUATION
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
                        reason=f"Take Profit hit ({tranche.target_sell_price:.2f})",
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
                                reason=f"Trailing Stop hit ({stop_price:.2f} > buy {tranche.buy_price:.2f})",
                                tranche_ref=tranche,
                            )
                        )
                        continue

        # 2. ENTRY EVALUATION
        if self.enable_compounding:
            total_effective_budget = max(
                self.config.budget,
                portfolio.total_budget + portfolio.total_realized_profit + portfolio.total_deposited_amount - portfolio.total_withdrawn_amount
            )
        else:
            total_effective_budget = self.config.budget

        macro_line = current_row.get(self.macro_indicator, 0.0)
        is_above_macro = close_price > macro_line if macro_line > 0 else True

        if regime == MarketRegime.BULL_TREND:
            t0_active = any(t.tranche_index == 0 and t.status == TrancheStatus.ACTIVE for t in active_tranches)
            if not t0_active:
                allocated_budget = total_effective_budget * self.trend_weight
                real_budget = min(allocated_budget, portfolio.available_usdt)
                if real_budget >= 10.0:
                    self.trend_entry_price = close_price
                    self.trend_highest_price = high_price
                    target_sell = close_price * (1.0 + self.config.take_profit_pct / 100.0)
                    signals.append(
                        ActionSignal(
                            signal_type=SignalType.BUY_TRANCHE,
                            symbol=self.config.symbol,
                            tranche_index=0,
                            price=close_price,
                            amount=real_budget / close_price,
                            allocated_usdt=real_budget,
                            target_sell_price=target_sell,
                            reason=f"BULL TREND ENTRY: Trend Following {self.trend_weight*100:.0f}%",
                        )
                    )

        elif regime == MarketRegime.RANGE:
            occupied_indices = {t.tranche_index for t in active_tranches if t.status == TrancheStatus.ACTIVE}

            # T0 Entry
            if 0 not in occupied_indices:
                if is_above_macro and rsi < self.t0_rsi_threshold:
                    weight_t0 = self.config.tranche_weights[0] if self.config.tranche_weights else 0.30
                    budget_t0 = total_effective_budget * weight_t0
                    real_budget = min(budget_t0, portfolio.available_usdt)
                    if real_budget >= 10.0:
                        target_sell = close_price * (1.0 + self.config.take_profit_pct / 100.0)
                        signals.append(
                            ActionSignal(
                                signal_type=SignalType.BUY_TRANCHE,
                                symbol=self.config.symbol,
                                tranche_index=0,
                                price=close_price,
                                amount=real_budget / close_price,
                                allocated_usdt=real_budget,
                                target_sell_price=target_sell,
                                reason=f"RANGE T0: Entry above {self.macro_indicator} with RSI {rsi:.1f}",
                            )
                        )

            # Deep tranches: T1 to T4
            chained_atr_multipliers = [2.0, 3.5, 5.5, 8.0]

            for i in range(1, self.config.max_tranches):
                if i not in occupied_indices:
                    prev_active = [t for t in active_tranches if t.tranche_index == (i - 1) and t.status == TrancheStatus.ACTIVE]
                    if prev_active:
                        prev_tranche = prev_active[0]
                        mult = chained_atr_multipliers[i - 1] if (i - 1) < len(chained_atr_multipliers) else 2.0 * i
                        threshold_price = prev_tranche.buy_price - (atr_14 * mult)

                        if close_price <= threshold_price:
                            weight_i = self.config.tranche_weights[i] if i < len(self.config.tranche_weights) else 0.15
                            budget_i = total_effective_budget * weight_i
                            real_budget = min(budget_i, portfolio.available_usdt)
                            if real_budget >= 10.0:
                                target_sell = close_price * (1.0 + self.config.take_profit_pct / 100.0)
                                signals.append(
                                    ActionSignal(
                                        signal_type=SignalType.BUY_TRANCHE,
                                        symbol=self.config.symbol,
                                        tranche_index=i,
                                        price=close_price,
                                        amount=real_budget / close_price,
                                        allocated_usdt=real_budget,
                                        target_sell_price=target_sell,
                                        reason=f"RANGE T{i}: Chained drop -{mult}x ATR ({threshold_price:.2f})",
                                    )
                                )
                            break

        elif regime == MarketRegime.PANIC_CAPITULATION:
            occupied_indices = {t.tranche_index for t in active_tranches if t.status == TrancheStatus.ACTIVE}
            if 0 not in occupied_indices and rsi < self.panic_rsi_threshold:
                sniper_budget = total_effective_budget * 0.35
                real_budget = min(sniper_budget, portfolio.available_usdt)
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
                            reason=f"QUANTUM PANIC: Sniper on exhaustion (RSI < {self.panic_rsi_threshold}, TP +7%)",
                        )
                    )

        return signals
