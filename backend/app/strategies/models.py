from enum import Enum
from typing import List, Optional


class MarketRegime(str, Enum):
    RANGE = "RANGE"
    BULL_TREND = "BULL_TREND"
    PANIC_CAPITULATION = "PANIC_CAPITULATION"
    UNKNOWN = "UNKNOWN"


class TrancheStatus(str, Enum):
    PENDING_BUY = "PENDING_BUY"
    ACTIVE = "ACTIVE"
    PENDING_SELL = "PENDING_SELL"
    CLOSED = "CLOSED"
    CANCELLED = "CANCELLED"


class SignalType(str, Enum):
    BUY_TRANCHE = "BUY_TRANCHE"
    SELL_TRANCHE = "SELL_TRANCHE"
    HOLD = "HOLD"
    CANCEL = "CANCEL"


class TrancheModel:
    def __init__(
        self,
        id: Optional[int],
        bot_id: str,
        symbol: str,
        tranche_index: int,
        allocated_budget: float,
        buy_price: float,
        amount: float,
        target_sell_price: float,
        status: TrancheStatus = TrancheStatus.ACTIVE,
        buy_fee: float = 0.0,
        sell_fee: float = 0.0,
        buy_timestamp: Optional[int] = None,
        sell_timestamp: Optional[int] = None,
        profit_usdt: float = 0.0,
        subsidized_satoshis: float = 0.0,
    ):
        self.id = id
        self.bot_id = bot_id
        self.symbol = symbol
        self.tranche_index = tranche_index
        self.allocated_budget = allocated_budget
        self.buy_price = buy_price
        self.amount = amount
        self.target_sell_price = target_sell_price
        self.status = status
        self.buy_fee = buy_fee
        self.sell_fee = sell_fee
        self.buy_timestamp = buy_timestamp
        self.sell_timestamp = sell_timestamp
        self.profit_usdt = profit_usdt
        self.subsidized_satoshis = subsidized_satoshis


class BotConfigModel:
    def __init__(
        self,
        bot_id: str,
        symbol: str,
        budget: float,
        take_profit_pct: float = 4.5,
        max_tranches: int = 8,
        tranche_weights: Optional[List[float]] = None,
        atr_multiplier: float = 1.5,
        trailing_stop_pct: float = 1.4,
        trend_weight: float = 0.70,
        t0_rsi_threshold: float = 48.0,
        panic_rsi_threshold: float = 28.0,
    ):
        self.bot_id = bot_id
        self.symbol = symbol
        self.budget = budget
        self.take_profit_pct = take_profit_pct
        self.max_tranches = max_tranches
        self.tranche_weights = tranche_weights or [0.30, 0.25, 0.20, 0.15, 0.10]
        self.atr_multiplier = atr_multiplier
        self.trailing_stop_pct = trailing_stop_pct
        self.trend_weight = trend_weight
        self.t0_rsi_threshold = t0_rsi_threshold
        self.panic_rsi_threshold = panic_rsi_threshold


class ActionSignal:
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
        tranche_ref: Optional[TrancheModel] = None,
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
    def __init__(
        self,
        symbol: str = "",
        total_budget: float = 0.0,
        available_usdt: float = 0.0,
        active_tranches: Optional[List[TrancheModel]] = None,
        completed_tranches: Optional[List[TrancheModel]] = None,
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
