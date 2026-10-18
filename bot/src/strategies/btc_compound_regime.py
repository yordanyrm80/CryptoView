from typing import List, Optional
import pandas as pd
from src.core.regime_detector import MarketRegimeDetector
from src.domain.models import BotConfig, MarketRegime, TrancheStatus
from src.strategies.base import ActionSignal, BaseStrategy, PortfolioState, SignalType



class BtcCompoundRegimeStrategy(BaseStrategy):
    """Quantitative Maximum Growth Strategy for Bitcoin (BTC/USDT).

    Key Features:
    - Dynamic Volatility Spacing: Chained ATR Spacing (2.0x, 3.5x, 5.5x, 8.0x ATR).
    - Front-Loaded Allocation: Weights [0.25, 0.20, 0.20, 0.20, 0.15] to maximize capital efficiency.
    - Dynamic Compounding: Scales operational budget with net realized profits and capital injections.
    - Resonant Exits: +5.0% TP in Range, 2.5% Trailing Stop in Bull Trend, and Capitulation Sniper.
    """

    def __init__(
        self,
        config: Optional[BotConfig] = None,
        enable_compounding: bool = True,
    ):
        if config is None:
            raise ValueError("A valid BotConfig is required.")
        super().__init__(config)
        self.enable_compounding = enable_compounding
        self.trend_highest_price: Optional[float] = None
        self.trend_entry_price: Optional[float] = None

    def evaluate(self, current_row: pd.Series, portfolio: PortfolioState) -> List[ActionSignal]:
        signals: List[ActionSignal] = []
        regime = MarketRegimeDetector.detect_regime(current_row)

        current_price = current_row["close"]
        high_price = current_row["high"]
        low_price = current_row["low"]
        atr_14 = current_row.get("atr_14", current_price * 0.02)
        rsi = current_row.get("rsi_14", 50.0)

        # -------------------------------------------------------------
        # 1. EXIT EVALUATION
        # -------------------------------------------------------------
        for tranche in list(portfolio.active_tranches):
            if tranche.status != TrancheStatus.ACTIVE:
                continue

            # A) Standard Take Profit exit (Range / Sniper)
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

            # B) Trailing Stop exit in Strong Bull Trend
            if regime == MarketRegime.BULL_TREND and self.trend_highest_price is not None:
                if high_price > self.trend_highest_price:
                    self.trend_highest_price = high_price

                stop_price = self.trend_highest_price * (1.0 - self.config.trailing_stop_pct / 100.0)
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
                                reason=f"Trailing Stop executed (+{((stop_price/tranche.buy_price)-1)*100:.1f}%)",
                                tranche_ref=tranche,
                            )
                        )
                        self.trend_highest_price = None

        if signals:
            return signals

        # -------------------------------------------------------------
        # 2. CAPITAL BASE CALCULATION (COMPOUNDING)
        # -------------------------------------------------------------
        if self.enable_compounding:
            net_profit = max(0.0, portfolio.total_realized_profit - portfolio.total_withdrawn_amount)
            effective_base = self.config.budget + portfolio.total_deposited_amount + net_profit
        else:
            effective_base = self.config.budget

        occupied = {t.tranche_index: t for t in portfolio.active_tranches if t.status == TrancheStatus.ACTIVE}

        # -------------------------------------------------------------
        # 3. ENTRY EVALUATION BY REGIME
        # -------------------------------------------------------------

        # REGIME 1: RANGE / SIDEWAYS MARKET (~70% of time)
        if regime == MarketRegime.RANGE:
            if len(occupied) == 0:
                ema_200 = current_row["ema_200"]
                # Macro filter: Price >= EMA 200 and healthy RSI (< 48)
                if current_price >= ema_200 and rsi < 48.0:
                    t0_budget = effective_base * self.config.tranche_weights[0]
                    if portfolio.available_usdt >= t0_budget:
                        signals.append(
                            ActionSignal(
                                signal_type=SignalType.BUY_TRANCHE,
                                symbol=self.config.symbol,
                                tranche_index=0,
                                price=current_price,
                                amount=t0_budget / current_price,
                                allocated_usdt=t0_budget,
                                target_sell_price=current_price * (1.0 + self.config.take_profit_pct / 100.0),
                                reason="BTC RANGE: Tranche 0 entry above EMA 200",
                            )
                        )
            else:
                highest_idx = max(occupied.keys())
                next_idx = highest_idx + 1

                if next_idx < self.config.max_tranches:
                    last_buy_price = occupied[highest_idx].buy_price
                    atr_multipliers = [2.0, 3.5, 5.5, 8.0]
                    mult = atr_multipliers[min(next_idx - 1, len(atr_multipliers) - 1)]
                    caida_requerida = atr_14 * mult
                    target_buy = last_buy_price - caida_requerida

                    if current_price <= target_buy:
                        tranche_budget = effective_base * self.config.tranche_weights[next_idx]
                        if portfolio.available_usdt >= tranche_budget:
                            signals.append(
                                ActionSignal(
                                    signal_type=SignalType.BUY_TRANCHE,
                                    symbol=self.config.symbol,
                                    tranche_index=next_idx,
                                    price=current_price,
                                    amount=tranche_budget / current_price,
                                    allocated_usdt=tranche_budget,
                                    target_sell_price=current_price * (1.0 + self.config.take_profit_pct / 100.0),
                                    reason=f"BTC RANGE: Chained T{next_idx} entry (-{caida_requerida:.2f} USDT from T{highest_idx})",
                                )
                            )

        # REGIME 2: STRONG BULL TREND
        elif regime == MarketRegime.BULL_TREND:
            if len(occupied) == 0:
                ema_50 = current_row["ema_50"]
                if current_price <= ema_50 * 1.015 or rsi < 55.0:
                    trend_budget = effective_base * 0.40
                    if portfolio.available_usdt >= trend_budget:
                        self.trend_highest_price = high_price
                        self.trend_entry_price = current_price
                        signals.append(
                            ActionSignal(
                                signal_type=SignalType.BUY_TRANCHE,
                                symbol=self.config.symbol,
                                tranche_index=0,
                                price=current_price,
                                amount=trend_budget / current_price,
                                allocated_usdt=trend_budget,
                                target_sell_price=current_price * 2.0,
                                reason="BTC TREND: Pullback entry with Trailing Stop",
                            )
                        )

        # REGIME 3: PANIC / CAPITULATION
        elif regime == MarketRegime.PANIC_CAPITULATION:
            if len(occupied) == 0 and rsi < 25.0:
                sniper_budget = effective_base * 0.35
                if portfolio.available_usdt >= sniper_budget:
                    signals.append(
                        ActionSignal(
                            signal_type=SignalType.BUY_TRANCHE,
                            symbol=self.config.symbol,
                            tranche_index=0,
                            price=current_price,
                            amount=sniper_budget / current_price,
                            allocated_usdt=sniper_budget,
                            target_sell_price=current_price * 1.05,
                            reason="BTC PANIC: Sniper shot on extreme capitulation (RSI < 25)",
                        )
                    )

        return signals

    # Backward compatibility alias
    evaluar = evaluate


# Backward compatibility aliases
EstrategiaRegimenCompuestoBtc = BtcCompoundRegimeStrategy
