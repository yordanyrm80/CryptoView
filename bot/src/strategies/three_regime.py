from typing import List, Optional
import pandas as pd
from src.core.regime_detector import MarketRegimeDetector
from src.domain.models import BotConfig, MarketRegime, TrancheStatus
from src.strategies.base import ActionSignal, BaseStrategy, PortfolioState, SignalType



class AdaptiveThreeRegimeStrategy(BaseStrategy):
    """Adaptive 3-Regime Quantitative Strategy (Range, Bull Trend, and Panic Capitulation)."""

    def __init__(self, config: Optional[BotConfig] = None):
        if config is None:
            raise ValueError("A valid BotConfig is required.")
        super().__init__(config)
        self.reference_price: Optional[float] = None
        self.trend_highest_price: Optional[float] = None
        self.trend_entry_price: Optional[float] = None

    def evaluate(self, current_row: pd.Series, portfolio: PortfolioState) -> List[ActionSignal]:
        signals: List[ActionSignal] = []
        regime = MarketRegimeDetector.detect_regime(current_row)

        current_price = current_row["close"]
        high_price = current_row["high"]
        low_price = current_row["low"]
        atr_pct = max(current_row.get("atr_pct", 2.0), 1.5)
        rsi = current_row.get("rsi_14", 50.0)

        # -------------------------------------------------------------
        # EXIT EVALUATION (Common to all active tranches)
        # -------------------------------------------------------------
        for tranche in list(portfolio.active_tranches):
            if tranche.status != TrancheStatus.ACTIVE:
                continue

            # A) Standard Take Profit exit (Range / Sniper mode)
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

            # B) Trailing Stop exit in Bull Trend (if applicable)
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
                                reason=f"Trailing Stop triggered (+{((stop_price/tranche.buy_price)-1)*100:.1f}%)",
                                tranche_ref=tranche,
                            )
                        )
                        self.trend_highest_price = None

        if signals:
            return signals

        # -------------------------------------------------------------
        # ENTRY EVALUATION BY REGIME
        # -------------------------------------------------------------
        occupied_indices = {t.tranche_index for t in portfolio.active_tranches if t.status == TrancheStatus.ACTIVE}

        # REGIME 1: RANGE / SIDEWAYS MARKET (~70% of time)
        if regime == MarketRegime.RANGE:
            step_pct = max(3.0, atr_pct * self.config.atr_multiplier)

            if len(occupied_indices) == 0:
                self.reference_price = current_price
                ema_200 = current_row["ema_200"]
                # Macro filter for Tranche 0:
                if current_price >= ema_200 and rsi < 48.0:
                    t0_budget = self.config.budget * self.config.tranche_weights[0]
                    if portfolio.available_usdt >= t0_budget:
                        target_sell = current_price * (1.0 + self.config.take_profit_pct / 100.0)
                        signals.append(
                            ActionSignal(
                                signal_type=SignalType.BUY_TRANCHE,
                                symbol=self.config.symbol,
                                tranche_index=0,
                                price=current_price,
                                amount=t0_budget / current_price,
                                allocated_usdt=t0_budget,
                                target_sell_price=target_sell,
                                reason="RANGE Regime: Tranche 0 entry above EMA 200",
                            )
                        )
                        return signals

            # Tranches 1 to 4: Geometrically spaced by ATR
            if self.reference_price is not None:
                multipliers = [1.0, 2.2, 4.0, 6.5]
                for idx in range(1, self.config.max_tranches):
                    if idx not in occupied_indices:
                        mult = multipliers[idx - 1]
                        required_drop = step_pct * mult
                        target_buy = self.reference_price * (1.0 - required_drop / 100.0)

                        if current_price <= target_buy:
                            tranche_budget = self.config.budget * self.config.tranche_weights[idx]
                            if portfolio.available_usdt >= tranche_budget:
                                target_sell = current_price * (1.0 + self.config.take_profit_pct / 100.0)
                                signals.append(
                                    ActionSignal(
                                        signal_type=SignalType.BUY_TRANCHE,
                                        symbol=self.config.symbol,
                                        tranche_index=idx,
                                        price=current_price,
                                        amount=tranche_budget / current_price,
                                        allocated_usdt=tranche_budget,
                                        target_sell_price=target_sell,
                                        reason=f"RANGE Regime: Tranche {idx} entry via ATR (-{required_drop:.1f}%)",
                                    )
                                )
                                break

        # REGIME 2: STRONG BULL TREND
        elif regime == MarketRegime.BULL_TREND:
            if len(occupied_indices) == 0:
                ema_50 = current_row["ema_50"]
                if current_price <= ema_50 * 1.015 or rsi < 55.0:
                    trend_budget = self.config.budget * 0.40
                    if portfolio.available_usdt >= trend_budget:
                        self.trend_highest_price = high_price
                        self.trend_entry_price = current_price
                        target_sell = current_price * 2.0
                        signals.append(
                            ActionSignal(
                                signal_type=SignalType.BUY_TRANCHE,
                                symbol=self.config.symbol,
                                tranche_index=0,
                                price=current_price,
                                amount=trend_budget / current_price,
                                allocated_usdt=trend_budget,
                                target_sell_price=target_sell,
                                reason="TREND Regime: Pullback entry with Trailing Stop",
                            )
                        )

        # REGIME 3: PANIC / CAPITULATION
        elif regime == MarketRegime.PANIC_CAPITULATION:
            if len(occupied_indices) == 0 and rsi < 25.0:
                sniper_budget = self.config.budget * 0.35
                if portfolio.available_usdt >= sniper_budget:
                    target_sell = current_price * 1.07
                    signals.append(
                        ActionSignal(
                            signal_type=SignalType.BUY_TRANCHE,
                            symbol=self.config.symbol,
                            tranche_index=0,
                            price=current_price,
                            amount=sniper_budget / current_price,
                            allocated_usdt=sniper_budget,
                            target_sell_price=target_sell,
                            reason="PANIC Regime: Sniper shot on extreme capitulation",
                        )
                    )

        return signals

    # Backward compatibility alias
    evaluar = evaluate


# Backward compatibility aliases
EstrategiaAdaptativaTresRegimenes = AdaptiveThreeRegimeStrategy

