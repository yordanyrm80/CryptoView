from typing import List, Optional
import pandas as pd
from src.core.regime_detector import MarketRegimeDetector
from src.domain.models import BotConfig, MarketRegime, TrancheStatus
from src.strategies.base import ActionSignal, BaseStrategy, PortfolioState, SignalType



class BtcUltraCompoundRegimeStrategy(BaseStrategy):
    """Quantitative Ultra-Compound High-Velocity Strategy for Bitcoin (BTC/USDT).

    Mathematical Advantages:
    - High-Rotation Front-Loaded Weights [0.30, 0.25, 0.20, 0.15, 0.10]:
      Puts 55% of capital directly into T0 & T1 (representing >85% of executions).
    - High-Frequency Trailing Stop Calibration (2.0% default):
      Locks profits quickly at candle tops, recycling capital faster without deep pullbacks.
    - Multi-Timeframe Macro Filter (Daily EMA 200 / 4,800h):
      Tranche 0 entry condition: Price >= Daily EMA 200 and RSI < 48.0.
    - Dynamic Chained ATR Spacing (2.0x, 3.5x, 5.5x, 8.0x ATR).
    """

    def __init__(
        self,
        config: Optional[BotConfig] = None,
        enable_compounding: bool = True,
        macro_indicator: str = "ema_daily_200",
        trailing_stop_pct: Optional[float] = None,
    ):
        if config is None:
            raise ValueError("A valid BotConfig is required.")
        super().__init__(config)
        self.enable_compounding = enable_compounding
        self.macro_indicator = macro_indicator
        self.trailing_stop_pct = trailing_stop_pct if trailing_stop_pct is not None else config.trailing_stop_pct

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

            # A) Standard Take Profit exit
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
                macro_val = current_row.get(self.macro_indicator, current_row["ema_200"])
                # Macro filter: Price >= Macro EMA and healthy RSI (< 48)
                if current_price >= macro_val and rsi < 48.0:
                    t0_budget = effective_base * self.config.tranche_weights[0]
                    actual_budget = min(t0_budget, portfolio.available_usdt)
                    if actual_budget >= 10.0:
                        signals.append(
                            ActionSignal(
                                signal_type=SignalType.BUY_TRANCHE,
                                symbol=self.config.symbol,
                                tranche_index=0,
                                price=current_price,
                                amount=actual_budget / current_price,
                                allocated_usdt=actual_budget,
                                target_sell_price=current_price * (1.0 + self.config.take_profit_pct / 100.0),
                                reason=f"BTC ULTRA RANGE: Tranche 0 entry above {self.macro_indicator} ({macro_val:.1f})",
                            )
                        )
            else:
                # Chained entries via volatility (Chained ATR)
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
                        actual_budget = min(tranche_budget, portfolio.available_usdt)
                        if actual_budget >= 10.0:
                            signals.append(
                                ActionSignal(
                                    signal_type=SignalType.BUY_TRANCHE,
                                    symbol=self.config.symbol,
                                    tranche_index=next_idx,
                                    price=current_price,
                                    amount=actual_budget / current_price,
                                    allocated_usdt=actual_budget,
                                    target_sell_price=current_price * (1.0 + self.config.take_profit_pct / 100.0),
                                    reason=f"BTC ULTRA RANGE: Chained T{next_idx} entry (-{caida_requerida:.2f} USDT)",
                                )
                            )

        # REGIME 2: STRONG BULL TREND
        elif regime == MarketRegime.BULL_TREND:
            if len(occupied) == 0:
                ema_50 = current_row["ema_50"]
                if current_price <= ema_50 * 1.015 or rsi < 55.0:
                    trend_budget = effective_base * 0.40
                    actual_budget = min(trend_budget, portfolio.available_usdt)
                    if actual_budget >= 10.0:
                        self.trend_highest_price = high_price
                        self.trend_entry_price = current_price
                        signals.append(
                            ActionSignal(
                                signal_type=SignalType.BUY_TRANCHE,
                                symbol=self.config.symbol,
                                tranche_index=0,
                                price=current_price,
                                amount=actual_budget / current_price,
                                allocated_usdt=actual_budget,
                                target_sell_price=current_price * 2.0,
                                reason=f"BTC ULTRA TREND: Pullback entry with calibrated Trailing Stop ({self.trailing_stop_pct}%)",
                            )
                        )

        # REGIME 3: PANIC / CAPITULATION
        elif regime == MarketRegime.PANIC_CAPITULATION:
            if len(occupied) == 0 and rsi < 25.0:
                sniper_budget = effective_base * 0.35
                actual_budget = min(sniper_budget, portfolio.available_usdt)
                if actual_budget >= 10.0:
                    signals.append(
                        ActionSignal(
                            signal_type=SignalType.BUY_TRANCHE,
                            symbol=self.config.symbol,
                            tranche_index=0,
                            price=current_price,
                            amount=actual_budget / current_price,
                            allocated_usdt=actual_budget,
                            target_sell_price=current_price * 1.05,
                            reason="BTC ULTRA PANIC: Sniper shot on extreme capitulation (RSI < 25)",
                        )
                    )

        return signals

    # Backward compatibility alias
    evaluar = evaluate


# Backward compatibility aliases
EstrategiaRegimenUltraCompuestoBtc = BtcUltraCompoundRegimeStrategy
