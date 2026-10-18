from enum import Enum
from typing import List, Optional
import pandas as pd
from src.domain.models import BotConfig, Tranche, TrancheStatus


class SignalType(str, Enum):
    """Action signals emitted by quantitative strategies."""
    BUY_TRANCHE = "BUY_TRANCHE"
    SELL_TRANCHE = "SELL_TRANCHE"
    HOLD = "HOLD"
    CANCEL = "CANCEL"


class ActionSignal:
    """Action signal emitted by a strategy for execution by portfolio runner."""

    def __init__(
        self,
        signal_type: SignalType = SignalType.HOLD,
        symbol: str = "",
        tranche_index: int = 0,
        price: float = 0.0,
        amount: float = 0.0,
        allocated_usdt: float = 0.0,
        reason: str = "",
        target_sell_price: Optional[float] = None,
        tranche_ref: Optional[Tranche] = None,
    ):
        self.signal_type = signal_type
        self.symbol = symbol
        self.tranche_index = tranche_index
        self.price = price
        self.amount = amount
        self.allocated_usdt = allocated_usdt
        self.reason = reason
        self.target_sell_price = target_sell_price
        self.tranche_ref = tranche_ref


class PortfolioState:
    """Snapshot of portfolio balance and tranche positions."""

    def __init__(
        self,
        symbol: str = "",
        total_budget: float = 0.0,
        available_usdt: float = 0.0,
        active_tranches: Optional[List[Tranche]] = None,
        completed_tranches: Optional[List[Tranche]] = None,
        total_realized_profit: float = 0.0,
        total_withdrawn_amount: float = 0.0,
        total_deposited_amount: float = 0.0,
    ):
        self.symbol = symbol
        self.total_budget = total_budget
        self.available_usdt = available_usdt
        self.active_tranches = active_tranches if active_tranches is not None else []
        self.completed_tranches = completed_tranches if completed_tranches is not None else []
        self.total_realized_profit = total_realized_profit
        self.total_withdrawn_amount = total_withdrawn_amount
        self.total_deposited_amount = total_deposited_amount
        self.subsidized_satoshis_total: float = 0.0
        self.harvested_btc_free: float = 0.0

    @property
    def invested_amount_usdt(self) -> float:
        return sum(
            t.allocated_budget for t in self.active_tranches if t.status == TrancheStatus.ACTIVE
        )

    @property
    def total_equity_est(self) -> float:
        return self.available_usdt + self.invested_amount_usdt


class BaseStrategy:
    """Base interface for all quantitative trading strategies."""

    def __init__(self, config: BotConfig):
        self.config = config

    def evaluate(self, current_row: pd.Series, portfolio: PortfolioState) -> List[ActionSignal]:
        raise NotImplementedError("Strategy subclasses must implement 'evaluate'.")
