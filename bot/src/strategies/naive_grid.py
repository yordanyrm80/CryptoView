from typing import List, Optional
import pandas as pd
from src.domain.models import BotConfig, Tranche, TrancheStatus
from src.strategies.base import ActionSignal, BaseStrategy, PortfolioState, SignalType



class NaiveGridStrategy(BaseStrategy):
    """Static Grid strategy without market regime filters (baseline initial model)."""

    def __init__(
        self,
        config: Optional[BotConfig] = None,
        fixed_drop_pcts: Optional[List[float]] = None,
    ):
        if config is None:
            raise ValueError("A valid BotConfig is required.")
        super().__init__(config)
        self.fixed_drop_pcts = fixed_drop_pcts or [0.0, 4.0, 10.0, 20.0, 35.0]
        self.reference_price: Optional[float] = None

    def evaluate(self, current_row: pd.Series, portfolio: PortfolioState) -> List[ActionSignal]:
        signals: List[ActionSignal] = []
        current_price = current_row["close"]
        high_price = current_row["high"]

        # 1. Check exits (Take Profit on active tranches)
        for tranche in list(portfolio.active_tranches):
            if tranche.status == TrancheStatus.ACTIVE:
                if high_price >= tranche.target_sell_price:
                    signals.append(
                        ActionSignal(
                            signal_type=SignalType.SELL_TRANCHE,
                            symbol=self.config.symbol,
                            tranche_index=tranche.tranche_index,
                            price=tranche.target_sell_price,
                            amount=tranche.amount,
                            allocated_usdt=tranche.allocated_budget,
                            reason=f"Take Profit hit (+{self.config.take_profit_pct}%)",
                            tranche_ref=tranche,
                        )
                    )

        # If no active tranches and no pending sell signals, reset reference price
        active_count = len([t for t in portfolio.active_tranches if t.status == TrancheStatus.ACTIVE])
        if active_count == 0 and not signals:
            self.reference_price = current_price

        if self.reference_price is None:
            self.reference_price = current_price

        # 2. Check entries for unoccupied tranches
        occupied_indices = {t.tranche_index for t in portfolio.active_tranches if t.status == TrancheStatus.ACTIVE}

        # If tranche 0 is not occupied, buy immediately at reference price
        if 0 not in occupied_indices and len(occupied_indices) == 0:
            t0_budget = self.config.budget * self.config.tranche_weights[0]
            if portfolio.available_usdt >= t0_budget:
                sell_target = current_price * (1.0 + self.config.take_profit_pct / 100.0)
                amount = t0_budget / current_price
                signals.append(
                    ActionSignal(
                        signal_type=SignalType.BUY_TRANCHE,
                        symbol=self.config.symbol,
                        tranche_index=0,
                        price=current_price,
                        amount=amount,
                        allocated_usdt=t0_budget,
                        target_sell_price=sell_target,
                        reason="Initial entry Tranche 0",
                    )
                )
                return signals

        # For tranches 1 to 4, enter if price dropped relative to reference price
        for idx in range(1, self.config.max_tranches):
            if idx not in occupied_indices:
                required_drop = self.fixed_drop_pcts[idx]
                target_buy_price = self.reference_price * (1.0 - required_drop / 100.0)

                if current_price <= target_buy_price:
                    tranche_budget = self.config.budget * self.config.tranche_weights[idx]
                    if portfolio.available_usdt >= tranche_budget:
                        sell_target = current_price * (1.0 + self.config.take_profit_pct / 100.0)
                        amount = tranche_budget / current_price
                        signals.append(
                            ActionSignal(
                                signal_type=SignalType.BUY_TRANCHE,
                                symbol=self.config.symbol,
                                tranche_index=idx,
                                price=current_price,
                                amount=amount,
                                allocated_usdt=tranche_budget,
                                target_sell_price=sell_target,
                                reason=f"Staggered buy Tranche {idx} (-{required_drop}%)",
                            )
                        )
                        break

        return signals

    # Backward compatibility alias
    evaluar = evaluate


# Backward compatibility aliases
EstrategiaGridIngenuo = NaiveGridStrategy

