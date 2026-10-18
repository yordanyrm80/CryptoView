import asyncio
import logging
from typing import Any, Optional
from src.core.event_bus import DomainEvent, EventBus
from src.core.telegram_notifier import TelegramNotifier
from src.core.discord_notifier import DiscordNotifier

logger = logging.getLogger(__name__)


class NotificationDispatcher:
    """Consumes domain events from EventBus and dispatches external notifications (Telegram, Discord).

    Completely isolated from the trading engine. Failures or latencies in external
    APIs never block or affect order execution.
    """

    _instance: Optional["NotificationDispatcher"] = None

    def __init__(
        self,
        event_bus: Optional[EventBus] = None,
        telegram_notifier: Optional[TelegramNotifier] = None,
        discord_notifier: Optional[DiscordNotifier] = None,
        settings_repo: Optional[Any] = None,
    ):
        self.event_bus = event_bus or EventBus.get_instance()
        self.settings_repo = settings_repo
        self.telegram = telegram_notifier or TelegramNotifier(settings_repo=settings_repo)
        self.discord = discord_notifier or DiscordNotifier(settings_repo=settings_repo)
        self._queue: asyncio.Queue = asyncio.Queue()
        self._worker_task: Optional[asyncio.Task] = None
        self._running: bool = False
        NotificationDispatcher._instance = self

    @classmethod
    def get_instance(cls) -> "NotificationDispatcher":
        if cls._instance is None:
            cls._instance = cls()
        return cls._instance


    def start(self) -> None:
        """Starts worker queue and registers event subscriptions."""
        if self._running:
            return
        self._running = True
        self._worker_task = asyncio.create_task(self._process_queue())

        self.event_bus.subscribe("TRANCHE_BOUGHT", self._on_event)
        self.event_bus.subscribe("TRANCHE_SOLD", self._on_event)
        self.event_bus.subscribe("BOT_LIFECYCLE_CHANGED", self._on_event)
        self.event_bus.subscribe("CAPITAL_ADJUSTED", self._on_event)
        self.event_bus.subscribe("SYSTEM_ALERT", self._on_event)
        logger.info("NotificationDispatcher started and subscribed to domain events.")

    def stop(self) -> None:
        """Stops worker queue."""
        self._running = False
        if self._worker_task and not self._worker_task.done():
            self._worker_task.cancel()

    async def _on_event(self, event: DomainEvent) -> None:
        """Enqueues received event for background processing."""
        await self._queue.put(event)

    async def _process_queue(self) -> None:
        """Processes notifications sequentially with error isolation."""
        while self._running:
            try:
                event = await self._queue.get()
                await self._dispatch(event)
                self._queue.task_done()
            except asyncio.CancelledError:
                break
            except Exception as e:
                logger.error(f"Error processing notification queue item: {e}", exc_info=True)

    async def _dispatch(self, event: DomainEvent) -> None:
        """Formats and delivers notifications to active channels with strict error isolation."""
        d = event.data

        # 1. Telegram Dispatching
        if self.telegram.enabled:
            try:
                if event.event_type == "TRANCHE_BOUGHT":
                    await self.telegram.notify_buy(
                        bot_id=event.bot_id,
                        tranche_index=d.get("tranche_index", 0),
                        symbol=d.get("symbol", "BTC/USDT"),
                        price=d.get("buy_price", 0.0),
                        amount=d.get("amount", 0.0),
                        allocated_usdt=d.get("allocated_budget", 0.0),
                        target_tp=d.get("target_sell_price", 0.0),
                        is_dry_run=d.get("is_dry_run", True),
                    )
                elif event.event_type == "TRANCHE_SOLD":
                    await self.telegram.notify_sell(
                        bot_id=event.bot_id,
                        tranche_index=d.get("tranche_index", 0),
                        symbol=d.get("symbol", "BTC/USDT"),
                        sell_price=d.get("sell_price", 0.0),
                        profit_usdt=d.get("profit_usdt", 0.0),
                        is_dry_run=d.get("is_dry_run", True),
                    )
                elif event.event_type == "BOT_LIFECYCLE_CHANGED":
                    status = d.get("status", "UNKNOWN")
                    msg = f"ℹ️ <b>[BOT STATE]</b> <code>{event.bot_id}</code> is now <b>{status}</b>."
                    await self.telegram.send_message(msg)
                elif event.event_type == "CAPITAL_ADJUSTED":
                    tx_type = d.get("type", "ADJUSTMENT")
                    amount = d.get("amount", 0.0)
                    reason = d.get("reason", "N/A")
                    msg = (
                        f"💳 <b>[CAPITAL {tx_type}]</b>\n"
                        f"🤖 <b>Bot:</b> <code>{event.bot_id}</code>\n"
                        f"💵 <b>Monto:</b> ${amount:.2f} USDT\n"
                        f"📝 <b>Motivo:</b> {reason}"
                    )
                    await self.telegram.send_message(msg)
            except Exception as e:
                logger.warning(f"Failed to dispatch Telegram alert for event {event.event_type}: {e}")

        # 2. Discord Webhook Dispatching
        if self.discord.enabled:
            try:
                if event.event_type == "TRANCHE_BOUGHT":
                    await self.discord.notify_buy(
                        bot_id=event.bot_id,
                        tranche_index=d.get("tranche_index", 0),
                        symbol=d.get("symbol", "BTC/USDT"),
                        price=d.get("buy_price", 0.0),
                        amount=d.get("amount", 0.0),
                        allocated_usdt=d.get("allocated_budget", 0.0),
                        target_tp=d.get("target_sell_price", 0.0),
                        is_dry_run=d.get("is_dry_run", True),
                    )
                elif event.event_type == "TRANCHE_SOLD":
                    await self.discord.notify_sell(
                        bot_id=event.bot_id,
                        tranche_index=d.get("tranche_index", 0),
                        symbol=d.get("symbol", "BTC/USDT"),
                        sell_price=d.get("sell_price", 0.0),
                        profit_usdt=d.get("profit_usdt", 0.0),
                        is_dry_run=d.get("is_dry_run", True),
                    )
                elif event.event_type == "BOT_LIFECYCLE_CHANGED":
                    status = d.get("status", "UNKNOWN")
                    details = f"Symbol: {d.get('symbol', 'N/A')} | Budget: ${d.get('budget', 0):,.2f} USDT" if "symbol" in d else ""
                    await self.discord.notify_bot_status(bot_id=event.bot_id, status=status, details=details)
                elif event.event_type == "CAPITAL_ADJUSTED":
                    tx_type = d.get("type", "ADJUSTMENT")
                    amount = d.get("amount", 0.0)
                    reason = d.get("reason", "N/A")
                    await self.discord.notify_capital_adjustment(bot_id=event.bot_id, tx_type=tx_type, amount=amount, reason=reason)
                elif event.event_type == "SYSTEM_ALERT":
                    title = d.get("title", "Alerta Operativa")
                    message = d.get("message", "Detalle no especificado")
                    severity = d.get("severity", "WARNING")
                    await self.discord.notify_alert(title=title, message=message, severity=severity)
            except Exception as e:
                logger.warning(f"Failed to dispatch Discord webhook alert for event {event.event_type}: {e}")
