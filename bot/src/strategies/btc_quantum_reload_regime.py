from typing import List, Optional
import pandas as pd
from src.core.regime_detector import MarketRegimeDetector
from src.domain.models import BotConfig, MarketRegime, TrancheStatus
from src.strategies.base import ActionSignal, PortfolioState, SignalType
from src.strategies.btc_quantum_compound_regime import BtcQuantumCompoundRegimeStrategy


class BtcQuantumReloadRegimeStrategy(BtcQuantumCompoundRegimeStrategy):
    """Quantum Strategy with Capital Injection and Floor Tranches support."""

    def __init__(
        self,
        config: BotConfig,
        enable_compounding: bool = True,
        macro_indicator: str = "ema_daily_200",
        trailing_stop_pct: Optional[float] = None,
        panic_rsi_threshold: float = 28.0,
        base_max_tranches: int = 5,
        extra_floor_tranches: int = 3,
        floor_tranche_weights: Optional[List[float]] = None,
    ):
        super().__init__(
            config=config,
            enable_compounding=enable_compounding,
            macro_indicator=macro_indicator,
            trailing_stop_pct=trailing_stop_pct,
            panic_rsi_threshold=panic_rsi_threshold,
        )
        self.base_max_tranches = base_max_tranches
        self.extra_floor_tranches = extra_floor_tranches
        self.floor_tranche_weights = floor_tranche_weights or [0.10, 0.10, 0.10]
        self.floor_atr_spacing = [2.5, 4.0, 6.0]

    def evaluate(self, current_row: pd.Series, portfolio: PortfolioState) -> List[ActionSignal]:
        signals = super().evaluate(current_row, portfolio)

        occupied_indices = {
            t.tranche_index for t in portfolio.active_tranches if t.status == TrancheStatus.ACTIVE
        }
        all_base_occupied = all(i in occupied_indices for i in range(self.base_max_tranches))

        if not all_base_occupied:
            return signals

        if portfolio.available_usdt < 50.0:
            return signals

        close_price = current_row["close"]
        atr_14 = current_row.get("atr_14", close_price * 0.02)
        rsi = current_row.get("rsi_14", 50.0)

        lowest_base = min(
            (t for t in portfolio.active_tranches if t.tranche_index < self.base_max_tranches and t.status == TrancheStatus.ACTIVE),
            key=lambda t: t.buy_price,
            default=None,
        )

        if lowest_base is None:
            return signals

        reference_floor_price = lowest_base.buy_price

        if self.enable_compounding:
            total_effective_budget = max(
                self.config.budget,
                portfolio.total_budget + portfolio.total_realized_profit + portfolio.total_deposited_amount - portfolio.total_withdrawn_amount
            )
        else:
            total_effective_budget = self.config.budget

        for idx_floor in range(self.extra_floor_tranches):
            target_idx = self.base_max_tranches + idx_floor

            if target_idx not in occupied_indices:
                mult = self.floor_atr_spacing[idx_floor] if idx_floor < len(self.floor_atr_spacing) else (3.0 * (idx_floor + 1))
                trigger_price = reference_floor_price - (atr_14 * mult)

                if close_price <= trigger_price and rsi < 45.0:
                    weight_f = self.floor_tranche_weights[idx_floor] if idx_floor < len(self.floor_tranche_weights) else 0.10
                    budget_f = total_effective_budget * weight_f
                    real_budget = min(budget_f, portfolio.available_usdt)

                    if real_budget >= 10.0:
                        target_sell = close_price * (1.0 + self.config.take_profit_pct / 100.0)
                        signals.append(
                            ActionSignal(
                                signal_type=SignalType.BUY_TRANCHE,
                                symbol=self.config.symbol,
                                tranche_index=target_idx,
                                price=close_price,
                                amount=real_budget / close_price,
                                allocated_usdt=real_budget,
                                target_sell_price=target_sell,
                                reason=(
                                    f"RELOAD FLOOR T{target_idx}: Floor entry after injection ({close_price:.2f} <= {trigger_price:.2f}, RSI {rsi:.1f})"
                                ),
                            )
                        )
                        break

        return signals
