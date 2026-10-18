import asyncio
import logging
from typing import List, Optional
from src.core.event_bus import DomainEvent, EventBus
from src.exchange.client import KuCoinClient
from src.exchange.cryptoview_client import CryptoViewClient
from src.storage.candle_repository import CandleRepository
from src.storage.database import DatabaseManager

logger = logging.getLogger("criptobot.ingestor")


class MarketDataIngestor:
    """Dedicated market data ingestion worker.

    Responsible exclusively for polling live OHLCV data from CryptoView Data Engine
    (with automatic fallback to KuCoin CCXT if needed) and persisting it into PostgreSQL.
    Completely decouples data acquisition from trading decision and order execution logic.
    """

    def __init__(
        self,
        db_manager: Optional[DatabaseManager] = None,
        candle_repo: Optional[CandleRepository] = None,
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
        self.cryptoview_client = cryptoview_client or CryptoViewClient()
        self.kucoin_client = kucoin_client or KuCoinClient()
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
        logger.info(f"MarketDataIngestor started for symbols: {', '.join(self.symbols)} (CryptoView API: {self.use_cryptoview})")

    def stop(self) -> None:
        """Stops background ingestion loop."""
        self._running = False
        if self._task and not self._task.done():
            self._task.cancel()
        logger.info("MarketDataIngestor stopped.")

    async def sync_once(self) -> int:
        """Performs a single fetch and upsert cycle across all active symbols."""
        total_saved = 0
        loop = asyncio.get_running_loop()

        for symbol in list(self.symbols):
            try:
                candles = None

                # 1. Primary: Fetch high-speed aggregated candles from CryptoView Cloud API
                if self.use_cryptoview:
                    try:
                        candles = await self.cryptoview_client.fetch_candles(
                            symbol=symbol,
                            timeframe="1h",
                            exchange=self.exchange,
                            limit=5,
                            auto_track=True,
                        )
                    except Exception as e:
                        logger.warning(
                            f"MarketDataIngestor: CryptoView API error for {symbol} ({e}), falling back to KuCoin CCXT..."
                        )

                # 2. Fallback: Query KuCoin CCXT directly if CryptoView returned no candles or failed
                if not candles and self.kucoin_client:
                    candles = await loop.run_in_executor(
                        None,
                        lambda s=symbol: self.kucoin_client.fetch_ohlcv(s, timeframe="1h", limit=5),
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
