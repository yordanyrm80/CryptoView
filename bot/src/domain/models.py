from datetime import datetime, timezone
from enum import Enum
from typing import List, Optional
from pydantic import BaseModel, Field


class MarketRegime(str, Enum):
    """Market regimes identified by the quantitative regime detector."""
    RANGE = "RANGE"
    BULL_TREND = "BULL_TREND"
    PANIC_CAPITULATION = "PANIC_CAPITULATION"
    UNKNOWN = "UNKNOWN"


class OrderSide(str, Enum):
    """Order side on exchange."""
    BUY = "BUY"
    SELL = "SELL"


class OrderType(str, Enum):
    """Execution order type."""
    LIMIT = "LIMIT"
    MARKET = "MARKET"


class OrderStatus(str, Enum):
    """Order execution lifecycle status."""
    PENDING = "PENDING"
    OPEN = "OPEN"
    FILLED = "FILLED"
    CLOSED = "CLOSED"
    CANCELLED = "CANCELLED"
    REJECTED = "REJECTED"


class TrancheStatus(str, Enum):
    """Operating lifecycle state of a strategy tranche."""
    PENDING_BUY = "PENDING_BUY"
    ACTIVE = "ACTIVE"
    PENDING_SELL = "PENDING_SELL"
    CLOSED = "CLOSED"
    CANCELLED = "CANCELLED"


class Candle(BaseModel):
    """OHLCV market candle model."""
    symbol: str
    timeframe: str
    timestamp: int  # UTC Milliseconds
    open: float
    high: float
    low: float
    close: float
    volume: float

    @property
    def dt(self) -> datetime:
        return datetime.fromtimestamp(self.timestamp / 1000.0, tz=timezone.utc)


class Order(BaseModel):
    """Order submitted to or tracked on the exchange."""
    id: Optional[str] = None
    bot_id: str
    symbol: str
    side: OrderSide
    order_type: OrderType
    price: float
    amount: float
    status: OrderStatus = OrderStatus.PENDING
    fee: float = 0.0
    created_at: int = Field(default_factory=lambda: int(datetime.now(timezone.utc).timestamp() * 1000))
    filled_at: Optional[int] = None


class Tranche(BaseModel):
    """Quantitative tranche model for accumulation and profit taking."""
    id: Optional[int] = None
    bot_id: str
    symbol: str
    tranche_index: int  # 0 to max_tranches - 1
    allocated_budget: float
    buy_price: float
    amount: float
    target_sell_price: float
    actual_sell_price: Optional[float] = None
    status: TrancheStatus = TrancheStatus.PENDING_BUY
    buy_fee: float = 0.0
    sell_fee: float = 0.0
    buy_timestamp: Optional[int] = None
    sell_timestamp: Optional[int] = None
    profit_usdt: float = 0.0
    subsidized_satoshis: float = 0.0


class BotConfig(BaseModel):
    """Operational parameters configuration for a bot instance."""
    bot_id: str
    symbol: str
    budget: float
    take_profit_pct: float
    max_tranches: int = 5
    tranche_weights: List[float] = Field(default_factory=lambda: [0.30, 0.25, 0.20, 0.15, 0.10])
    atr_multiplier: float = 1.5
    trailing_stop_pct: float = 2.0
    trend_weight: float = 0.70
    enabled: bool = True
    # Subaccount isolated API keys for KuCoin
    subaccount_name: Optional[str] = None
    api_key: Optional[str] = None
    api_secret: Optional[str] = None
    api_passphrase: Optional[str] = None


class CapitalTransactionType(str, Enum):
    WITHDRAWAL = "WITHDRAWAL"
    DEPOSIT = "DEPOSIT"


class CapitalTransaction(BaseModel):
    """Record of a capital deposit or withdrawal on a bot instance."""
    id: Optional[int] = None
    bot_id: str
    type: str  # WITHDRAWAL, DEPOSIT
    amount: float
    available_after: float
    timestamp: int
    reason: Optional[str] = None


class BotEvent(BaseModel):
    """Audit log entry for bot state transitions and operational actions."""
    id: Optional[int] = None
    bot_id: str
    event_type: str
    details: Optional[str] = None
    timestamp: int


class BotInstance:
    """Domain model representing an active or dry-run instance of a trading bot."""

    def __init__(
        self,
        config: BotConfig,
        strategy_name: str,
        dry_run: bool = True,
    ):
        self.config = config
        self.strategy_name = strategy_name
        self.dry_run = dry_run

        self.status: str = "RUNNING"  # RUNNING, PAUSED, STOPPED
        self.active_tranches: List[Tranche] = []
        self.completed_tranches: List[Tranche] = []
        self.total_realized_profit: float = 0.0
        self.total_withdrawn_amount: float = 0.0
        self.total_deposited_amount: float = 0.0
        self.available_usdt: float = config.budget
        self.equity_history: List[float] = [config.budget]

