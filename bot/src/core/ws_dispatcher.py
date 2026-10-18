import logging
from typing import Optional
from src.api.routes.ws import manager
from src.core.event_bus import DomainEvent, EventBus

logger = logging.getLogger(__name__)


class WebSocketDispatcher:
    """Subscribes to domain events and broadcasts updates to connected Flutter UI clients."""

    def __init__(self, event_bus: Optional[EventBus] = None):
        self.event_bus = event_bus or EventBus.get_instance()
        self._running: bool = False

    def start(self) -> None:
        """Registers event handlers on EventBus."""
        if self._running:
            return
        self._running = True

        self.event_bus.subscribe("TRANCHE_BOUGHT", self._on_tranche_bought)
        self.event_bus.subscribe("TRANCHE_SOLD", self._on_tranche_sold)
        self.event_bus.subscribe("BOT_STATUS_UPDATED", self._on_status_updated)
        self.event_bus.subscribe("BOT_LIFECYCLE_CHANGED", self._on_lifecycle_changed)
        logger.info("WebSocketDispatcher started and subscribed to domain events.")

    def stop(self) -> None:
        self._running = False

    async def _on_tranche_bought(self, event: DomainEvent) -> None:
        await manager.broadcast_event(
            "tranche_bought",
            {
                "bot_id": event.bot_id,
                **event.data,
            },
        )

    async def _on_tranche_sold(self, event: DomainEvent) -> None:
        await manager.broadcast_event(
            "tranche_sold",
            {
                "bot_id": event.bot_id,
                **event.data,
            },
        )

    async def _on_status_updated(self, event: DomainEvent) -> None:
        await manager.broadcast_event(
            "bot_status_update",
            {
                "bot_id": event.bot_id,
                **event.data,
            },
        )

    async def _on_lifecycle_changed(self, event: DomainEvent) -> None:
        await manager.broadcast_event(
            "bot_lifecycle_update",
            {
                "bot_id": event.bot_id,
                **event.data,
            },
        )
