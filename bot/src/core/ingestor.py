import asyncio
import logging
from typing import List, Optional
from src.core.event_bus import DomainEvent, EventBus
from src.data_provider import MarketDataProvider, get_market_data_provider
from src.exchange.client import KuCoinClient
from src.exchange.cryptoview_client import CryptoViewClient
from src.storage.candle_repository import CandleRepository
from src.storage.database import DatabaseManager

logger = logging.getLogger("criptobot.ingestor")


class MarketDataIngestor:
    """Dedicated market data ingestion worker.

    Responsible exclusively for polling live OHLCV data via MarketDataProvider
    (Direct TimescaleDB when local or CryptoView REST API when remote)
    and persisting it into the bot repository.
    Completely decouples data acquisition from trading decision and order execution logic.
    """

    def __init__(
        self,
        db_manager: Optional[DatabaseManager] = None,
        candle_repo: Optional[CandleRepository] = None,
        data_provider: Optional[MarketDataProvider] = None,
        cryptoview_client: Optional[CryptoViewClient] = None,
        kucoin_client: Optional[KuCoinClient] = None,
        event_bus: Optional[EventBus] = None,
        symbols: Optional[List[str]] = None,
        poll_interval_seconds: float = 15.0,
        exchange: str = "kucoin",
        use_cryptoview: bool = True,
    ):
        self.db_manager = db_manager or DatabaseManager()
        self.candle_repo = candle_repo or CandleRepository(self.db_manager)
        if data_provider is not None:
            self.data_provider = data_provider
        elif cryptoview_client is not None:
            from src.data_provider.api_provider import ApiMarketDataProvider
            self.data_provider = ApiMarketDataProvider(client=cryptoview_client)
        else:
            self.data_provider = get_market_data_provider()
        self.cryptoview_client = getattr(self.data_provider, "client", cryptoview_client)
        self.kucoin_client = kucoin_client
        self.event_bus = event_bus or EventBus.get_instance()
        self.symbols = symbols or ["BTC/USDT"]
        self.poll_interval_seconds = poll_interval_seconds
        self.exchange = exchange
        self.use_cryptoview = use_cryptoview
        self._running: bool = False
        self._task: Optional[asyncio.Task] = None

    def add_symbol(self, symbol: str) -> None:
        """Adds a new symbol to the active ingestion list."""
        if symbol not in self.symbols:
            self.symbols.append(symbol)
            logger.info(f"MarketDataIngestor added tracked symbol: {symbol}")

    def start(self) -> None:
        """Starts background ingestion loop."""
        if self._running:
            return
        self._running = True
        self._task = asyncio.create_task(self._loop())
        logger.info(
            f"MarketDataIngestor started for symbols: {', '.join(self.symbols)} (Provider: {self.data_provider.__class__.__name__})"
        )

    def stop(self) -> None:
        """Stops background ingestion loop."""
        self._running = False
        if self._task and not self._task.done():
            self._task.cancel()
        logger.info("MarketDataIngestor stopped.")

    async def sync_once(self) -> int:
        """Performs a single fetch and upsert cycle across all active symbols via MarketDataProvider."""
        total_saved = 0

        for symbol in list(self.symbols):
            try:
                candles = await self.data_provider.get_candles(
                    symbol=symbol,
                    timeframe="1h",
                    exchange=self.exchange,
                    limit=5,
                )

                if candles:
                    saved = self.candle_repo.save_candles(candles)
                    total_saved += saved
                    latest = candles[-1]
                    self.event_bus.publish(
                        DomainEvent(
                            event_type="CANDLE_INGESTED",
                            bot_id="system_ingestor",
                            data={
                                "symbol": symbol,
                                "timeframe": "1h",
                                "timestamp": latest.timestamp,
                                "close": latest.close,
                                "saved_count": saved,
                            },
                        )
                    )
            except Exception as e:
                logger.warning(f"MarketDataIngestor transient error syncing {symbol}: {e}")

        return total_saved

    async def _loop(self) -> None:
        """Continuous background loop with backoff."""
        while self._running:
            try:
                await self.sync_once()
            except asyncio.CancelledError:
                break
            except Exception as e:
                logger.error(f"Unexpected error in MarketDataIngestor loop: {e}", exc_info=True)

            try:
                await asyncio.sleep(self.poll_interval_seconds)
            except asyncio.CancelledError:
                break
