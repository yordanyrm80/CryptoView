import logging
from contextlib import asynccontextmanager
from dotenv import load_dotenv
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

load_dotenv()

from src.api.routes.bots import router as bots_router
from src.api.routes.metrics import router as metrics_router
from src.api.routes.system import router as system_router
from src.api.routes.ws import router as ws_router
from src.core.event_bus import EventBus
from src.core.ingestor import MarketDataIngestor
from src.core.live_runner import LiveRunner
from src.core.notification_dispatcher import NotificationDispatcher
from src.core.ws_dispatcher import WebSocketDispatcher

from src.storage.database import DatabaseManager
from src.storage.settings_repository import SettingsRepository

logger = logging.getLogger("criptobot_api")

# Decoupled domain services
event_bus = EventBus.get_instance()
db_manager = DatabaseManager()
settings_repository = SettingsRepository(db_manager)
ingestor = MarketDataIngestor(symbols=["BTC/USDT"])
notification_dispatcher = NotificationDispatcher(event_bus=event_bus, settings_repo=settings_repository)
ws_dispatcher = WebSocketDispatcher(event_bus=event_bus)
live_runner = LiveRunner(event_bus=event_bus, db_manager=db_manager)


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Lifecycle context manager orchestrating decoupled background services."""
    logger.info("Initializing CriptoBot Decoupled Services...")
    notification_dispatcher.start()
    ws_dispatcher.start()
    ingestor.start()
    await live_runner.start()
    logger.info("All CriptoBot production services active.")
    yield
    logger.info("Shutting down CriptoBot production services...")
    live_runner.stop()
    ingestor.stop()
    notification_dispatcher.stop()
    ws_dispatcher.stop()
    logger.info("All CriptoBot services terminated cleanly.")


def create_app() -> FastAPI:
    """Creates and configures the FastAPI application for CriptoBot."""
    app = FastAPI(
        title="CriptoBot Institutional API",
        description="Institutional control, telemetry, and real-time WebSocket API for CriptoBot.",
        version="1.0.0",
        lifespan=lifespan,
    )

    # CORS configuration for Flutter client (mobile, web, desktop)
    app.add_middleware(
        CORSMiddleware,
        allow_origins=["*"],
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )

    # Include API routers
    app.include_router(bots_router, prefix="/api/v1")
    app.include_router(metrics_router, prefix="/api/v1")
    app.include_router(system_router, prefix="/api/v1")
    app.include_router(ws_router)

    @app.get("/", tags=["Root"])
    def root():
        return {
            "name": "CriptoBot API",
            "version": "1.0.0",
            "status": "online",
            "network": "Tailscale Mesh VPN Isolated",
            "architecture": "Event-Driven Decoupled (Ingestor, LiveRunner, EventBus, Dispatchers)",
            "docs": "/docs",
        }

    return app


app = create_app()
