from abc import ABC, abstractmethod
from typing import Any, Dict, List, Optional
from src.domain.models import Candle


class MarketDataProvider(ABC):
    """Abstract interface for acquiring market data.
    
    Decouples the bot's trading strategies, ingestors, and runners from the concrete
    data transport (direct PostgreSQL/TimescaleDB vs remote CryptoView REST API).
    """

    @abstractmethod
    async def get_candles(
        self,
        symbol: str,
        timeframe: str = "1h",
        exchange: str = "kucoin",
        limit: int = 500,
        start_time_ms: Optional[int] = None,
        end_time_ms: Optional[int] = None,
    ) -> List[Candle]:
        """Asynchronously fetches OHLCV candles."""
        pass

    @abstractmethod
    def get_candles_sync(
        self,
        symbol: str,
        timeframe: str = "1h",
        exchange: str = "kucoin",
        limit: int = 500,
        start_time_ms: Optional[int] = None,
        end_time_ms: Optional[int] = None,
    ) -> List[Candle]:
        """Synchronously fetches OHLCV candles for non-async contexts."""
        pass

    @abstractmethod
    async def get_ticker(
        self,
        symbol: str,
        exchange: str = "kucoin",
    ) -> Optional[Dict[str, Any]]:
        """Fetches the latest live price and candle stats for a symbol."""
        pass

    @abstractmethod
    async def close(self) -> None:
        """Closes any underlying network connections or database pools."""
        pass
