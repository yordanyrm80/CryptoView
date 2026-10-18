from typing import List, Optional
from pydantic import BaseModel, Field


class TrancheResponse(BaseModel):
    """Response schema for operational tranche details."""
    tranche_index: int
    allocated_budget: float
    buy_price: float
    amount: float
    target_sell_price: float
    status: str
    profit_usdt: float = 0.0
    buy_timestamp: Optional[int] = None
    sell_timestamp: Optional[int] = None


class BotSummaryResponse(BaseModel):
    """Consolidated summary for a trading bot."""
    bot_id: str
    symbol: str
    strategy_name: str = "BtcQuantumCompoundRegimeStrategy"
    budget: float
    status: str = Field(..., description="RUNNING, PAUSED, or STOPPED")
    dry_run: bool = True
    active_tranches_count: int = 0
    invested_amount_usdt: float = 0.0
    available_usdt: float = 0.0
    total_realized_profit_usdt: float = 0.0
    total_withdrawn_usdt: float = 0.0
    total_deposited_usdt: float = 0.0
    current_equity_usdt: float = 0.0
    win_rate_pct: float = 0.0
    total_trades: int = 0
    is_plateau_phase: bool = True
    capital_injection_recommended: bool = True
    capital_injection_advice: str = ""
    subaccount_name: Optional[str] = None
    has_custom_credentials: bool = False


class CapitalTransactionRequest(BaseModel):
    """Request schema for depositing or withdrawing capital."""
    amount: float = Field(..., gt=0.0, description="Amount in USDT")
    reason: Optional[str] = Field(default="Manual operation", description="Reason or note")


class CapitalTransactionResponse(BaseModel):
    """Response after executing a deposit or withdrawal."""
    bot_id: str
    type: str  # WITHDRAWAL, DEPOSIT
    amount: float
    available_usdt_after: float
    total_deposited_usdt: float
    total_withdrawn_usdt: float
    timestamp: int
    message: str


class CapitalTransactionItemResponse(BaseModel):
    """Individual transaction item in audit history."""
    id: Optional[int] = None
    bot_id: str
    type: str
    amount: float
    available_after: float
    timestamp: int
    reason: Optional[str] = None


class BotEventResponse(BaseModel):
    """Audit log event entry for a bot."""
    id: Optional[int] = None
    bot_id: str
    event_type: str
    details: Optional[str] = None
    timestamp: int


class PlateauStatusResponse(BaseModel):
    """Plateau phase status and capital injection recommendation."""
    bot_id: str
    is_plateau_phase: bool
    active_tranches_count: int
    max_tranches: int
    available_usdt: float
    current_market_regime: str
    capital_injection_recommended: bool
    advice: str


class CreateBotRequest(BaseModel):
    """Request schema for creating and deploying a bot."""
    bot_id: str
    symbol: str
    strategy_name: str = "BtcQuantumCompoundRegimeStrategy"
    budget: float
    dry_run: bool = True
    take_profit_pct: float = 5.0
    trailing_stop_pct: float = 2.0
    max_tranches: int = 5
    tranche_weights: Optional[List[float]] = None
    trend_weight: float = 0.70
    subaccount_name: Optional[str] = None
    api_key: Optional[str] = None
    api_secret: Optional[str] = None
    api_passphrase: Optional[str] = None


class MetricsOverviewResponse(BaseModel):
    """System-wide portfolio metrics overview."""
    total_portfolio_equity_usdt: float
    total_cash_flow_extracted_usdt: float
    active_bots_count: int
    total_open_positions_usdt: float
    system_win_rate_pct: float
    total_closed_trades: int


class EquityPointResponse(BaseModel):
    """Historical equity data point for charts."""
    timestamp: int
    equity: float
    cash_flow: float


class SystemHealthResponse(BaseModel):
    """System health check response."""
    status: str
    database_connected: bool
    active_bots: int
    dry_run_mode_global: bool
    app_version: str


class DiscordSettingsSchema(BaseModel):
    """Discord notification configuration details."""
    enabled: bool
    webhook_url_masked: str
    is_configured: bool


class TelegramSettingsSchema(BaseModel):
    """Telegram notification configuration details."""
    enabled: bool
    bot_token_masked: str
    chat_id_masked: str
    is_configured: bool


class SystemSettingsResponse(BaseModel):
    """Aggregated operational settings for administration client."""
    discord: DiscordSettingsSchema
    telegram: TelegramSettingsSchema
    dry_run_global: bool
    app_version: str


class UpdateSystemSettingsRequest(BaseModel):
    """Payload for updating dynamic system settings."""
    discord_webhook_url: Optional[str] = None
    discord_enabled: Optional[bool] = None
    telegram_bot_token: Optional[str] = None
    telegram_chat_id: Optional[str] = None
    telegram_enabled: Optional[bool] = None


class NotificationTestRequest(BaseModel):
    """Payload to trigger an immediate test notification."""
    channel: str = "discord"


class NotificationTestResponse(BaseModel):
    """Result of notification test trigger."""
    status: str
    channel: str
    message: str
    dispatched_at: str
