import asyncio
import logging
import time
from dataclasses import dataclass, field
from typing import Any, Callable, Coroutine, Dict, List, Optional

logger = logging.getLogger(__name__)


@dataclass(frozen=True)
class DomainEvent:
    """Immutable domain event representing state changes in the trading ecosystem."""

    event_type: str
    bot_id: str
    data: Dict[str, Any] = field(default_factory=dict)
    timestamp: int = field(default_factory=lambda: int(time.time() * 1000))


EventHandler = Callable[[DomainEvent], Coroutine[Any, Any, None]]


class EventBus:
    """Asynchronous in-process Publish-Subscribe event bus.

    Ensures complete decoupling between the trading execution engine and
    secondary side-effect consumers (Telegram alerts, WebSocket telemetry, analytics).
    """

    _instance: Optional["EventBus"] = None

    def __init__(self):
        self._subscribers: Dict[str, List[EventHandler]] = {}
        self._global_subscribers: List[EventHandler] = []
        try:
            self._main_loop: Optional[asyncio.AbstractEventLoop] = asyncio.get_running_loop()
        except RuntimeError:
            self._main_loop = None

    @classmethod
    def get_instance(cls) -> "EventBus":
        if cls._instance is None:
            cls._instance = cls()
        return cls._instance

    def subscribe(self, event_type: str, handler: EventHandler) -> None:
        """Subscribes an async handler to a specific event type."""
        if event_type not in self._subscribers:
            self._subscribers[event_type] = []
        if handler not in self._subscribers[event_type]:
            self._subscribers[event_type].append(handler)
            logger.debug(f"Subscribed handler {handler.__name__} to event {event_type}")

    def subscribe_all(self, handler: EventHandler) -> None:
        """Subscribes an async handler to all emitted domain events."""
        if handler not in self._global_subscribers:
            self._global_subscribers.append(handler)
            logger.debug(f"Subscribed global handler {handler.__name__}")

    def unsubscribe(self, event_type: str, handler: EventHandler) -> None:
        """Unsubscribes an async handler from an event type."""
        if event_type in self._subscribers and handler in self._subscribers[event_type]:
            self._subscribers[event_type].remove(handler)


    def publish(self, event: DomainEvent) -> None:
        """Publishes a domain event asynchronously without blocking the caller."""
        handlers = list(self._subscribers.get(event.event_type, [])) + list(self._global_subscribers)
        if not handlers:
            return

        try:
            loop = asyncio.get_running_loop()
            self._main_loop = loop
            for handler in handlers:
                loop.create_task(self._safe_dispatch(handler, event))
        except RuntimeError:
            if self._main_loop and self._main_loop.is_running():
                for handler in handlers:
                    asyncio.run_coroutine_threadsafe(self._safe_dispatch(handler, event), self._main_loop)
            else:
                logger.debug(f"No active event loop found to dispatch event {event.event_type}")

    async def _safe_dispatch(self, handler: EventHandler, event: DomainEvent) -> None:
        """Safely executes an event handler, isolating failures from publisher and other subscribers."""
        try:
            await handler(event)
        except Exception as e:
            logger.error(
                f"Error in event handler {getattr(handler, '__name__', str(handler))} for event {event.event_type}: {e}",
                exc_info=True,
            )
