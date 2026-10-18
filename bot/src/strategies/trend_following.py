from typing import List, Optional
import pandas as pd
from src.domain.models import BotConfig, TrancheStatus
from src.strategies.base import ActionSignal, BaseStrategy, PortfolioState, SignalType



class TrendFollowingStrategy(BaseStrategy):
    """Quantitative Trend Following and Volatility Breakout Strategy (Donchian Breakout + ATR Chandelier Exit)."""

    def __init__(
        self,
        config: Optional[BotConfig] = None,
        atr_stop_multiplier: float = 2.8,
        max_initial_risk_pct: float = 4.0,
        position_size_pct: float = 0.85,
    ):
        if config is None:
            raise ValueError("A valid BotConfig is required.")
        super().__init__(config)
        self.atr_stop_multiplier = atr_stop_multiplier
        self.max_initial_risk_pct = max_initial_risk_pct
        self.position_size_pct = position_size_pct

        self.entry_price: Optional[float] = None
        self.highest_high_since_entry: Optional[float] = None

    def evaluate(self, current_row: pd.Series, portfolio: PortfolioState) -> List[ActionSignal]:
        signals: List[ActionSignal] = []

        current_close = current_row["close"]
        high_price = current_row["high"]
        low_price = current_row["low"]
        ema_200 = current_row.get("ema_200", current_close)
        atr_14 = current_row.get("atr_14", current_close * 0.02)
        adx_14 = current_row.get("adx_14", 20.0)
        donchian_high = current_row.get("donchian_high_48", current_close)

        active_tranches = [t for t in portfolio.active_tranches if t.status == TrancheStatus.ACTIVE]

        # -----------------------------------------------------------------
        # 1. OPEN POSITION MANAGEMENT (EXITS VIA TRAILING STOP)
        # -----------------------------------------------------------------
        if len(active_tranches) > 0:
            tranche = active_tranches[0]

            if self.highest_high_since_entry is None:
                self.highest_high_since_entry = high_price
            else:
                self.highest_high_since_entry = max(self.highest_high_since_entry, high_price)

            if self.entry_price is None:
                self.entry_price = tranche.buy_price

            # Dynamic Chandelier Stop: Highest High - (N * ATR)
            chandelier_stop = self.highest_high_since_entry - (self.atr_stop_multiplier * atr_14)
            # Initial hard risk protection stop
            hard_stop = self.entry_price * (1.0 - self.max_initial_risk_pct / 100.0)

            # Effective stop is the higher of the two (ratchets up, never down)
            effective_stop = max(chandelier_stop, hard_stop)

            if low_price <= effective_stop:
                realized_pct = ((effective_stop / self.entry_price) - 1.0) * 100.0
                signals.append(
                    ActionSignal(
                        signal_type=SignalType.SELL_TRANCHE,
                        symbol=self.config.symbol,
                        tranche_index=tranche.tranche_index,
                        price=effective_stop,
                        amount=tranche.amount,
                        allocated_usdt=tranche.allocated_budget,
                        reason=f"Trend Exit (Trailing Stop executed at {effective_stop:.2f} [{realized_pct:+.1f}%])",
                        tranche_ref=tranche,
                    )
                )
                self.entry_price = None
                self.highest_high_since_entry = None
                return signals

            return signals

        # -----------------------------------------------------------------
        # 2. ENTRY EVALUATION (BULL BREAKOUT WITH CONFIRMATION)
        # -----------------------------------------------------------------
        if current_close >= donchian_high and current_close > ema_200 and adx_14 >= 18.0:
            deploy_budget = portfolio.available_usdt * self.position_size_pct
            if deploy_budget >= 50.0:
                self.entry_price = current_close
                self.highest_high_since_entry = high_price

                # In Trend Following there is no fixed take profit; trailing stop exits
                target_sell = current_close * 5.0

                signals.append(
                    ActionSignal(
                        signal_type=SignalType.BUY_TRANCHE,
                        symbol=self.config.symbol,
                        tranche_index=0,
                        price=current_close,
                        amount=deploy_budget / current_close,
                        allocated_usdt=deploy_budget,
                        target_sell_price=target_sell,
                        reason="Trend Breakout: 48h Donchian breakout confirmed above EMA 200",
                    )
                )

        return signals

    # Backward compatibility alias
    evaluar = evaluate


# Backward compatibility aliases
EstrategiaSeguimientoTendencia = TrendFollowingStrategy

