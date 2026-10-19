import logging
import os
from typing import Any, Dict, List, Optional
import httpx
from src.data_provider.base import MarketDataProvider
from src.domain.models import Candle
from src.exchange.cryptoview_client import CryptoViewClient

logger = logging.getLogger("criptobot.data_provider.api")


class ApiMarketDataProvider(MarketDataProvider):
    """Remote market data provider querying CryptoView REST API over HTTPS.
    
    Used when the bot is deployed on a different machine, server, or local PC.
    Fetches high-speed aggregated candles and live tickers from the CryptoView API
    using API key authentication without needing direct database port access.
    """

    def __init__(
        self,
        base_url: Optional[str] = None,
        api_key: Optional[str] = None,
        timeout: float = 15.0,
        client: Optional[CryptoViewClient] = None,
    ):
        self.base_url = (base_url or os.getenv("CRYPTOVIEW_API_URL", "https://129-146-110-196.sslip.io")).rstrip("/")
        self.api_key = api_key or os.getenv("CRYPTOVIEW_API_KEY", "")
        self.timeout = timeout
        self.client = client or CryptoViewClient(base_url=self.base_url, api_key=self.api_key, timeout=self.timeout)
        logger.info(f"ApiMarketDataProvider initialized pointing to {self.base_url}")

    async def get_candles(
        self,
        symbol: str,
        timeframe: str = "1h",
        exchange: str = "kucoin",
        limit: int = 500,
        start_time_ms: Optional[int] = None,
        end_time_ms: Optional[int] = None,
    ) -> List[Candle]:
        """Fetches OHLCV candles from CryptoView API asynchronously."""
        kwargs: Dict[str, Any] = {
            "symbol": symbol,
            "timeframe": timeframe,
            "exchange": exchange,
            "limit": limit,
            "auto_track": True,
        }
        if start_time_ms is not None:
            kwargs["start_time_ms"] = start_time_ms
        if end_time_ms is not None:
            kwargs["end_time_ms"] = end_time_ms

        return await self.client.fetch_candles(**kwargs)

    def get_candles_sync(
        self,
        symbol: str,
        timeframe: str = "1h",
        exchange: str = "kucoin",
        limit: int = 500,
        start_time_ms: Optional[int] = None,
        end_time_ms: Optional[int] = None,
    ) -> List[Candle]:
        """Fetches OHLCV candles from CryptoView API synchronously."""
        return self.client.fetch_candles_sync(
            symbol=symbol,
            timeframe=timeframe,
            exchange=exchange,
            limit=limit,
            start_time_ms=start_time_ms,
            end_time_ms=end_time_ms,
            auto_track=True,
        )

    async def get_ticker(
        self,
        symbol: str,
        exchange: str = "kucoin",
    ) -> Optional[Dict[str, Any]]:
        """Fetches live ticker from CryptoView API /api/v1/candles/tickers."""
        url = f"{self.base_url}/api/v1/candles/tickers"
        clean_symbol = symbol.replace("-", "/").upper()
        clean_exchange = exchange.lower().strip()

        try:
            async with httpx.AsyncClient(timeout=self.timeout) as http_client:
                resp = await http_client.get(url, headers=self.client.headers)
                if resp.status_code == 200:
                    tickers = resp.json()
                    for t in tickers:
                        if t.get("exchange", "").lower() == clean_exchange and t.get("symbol", "").upper() == clean_symbol:
                            return t
        except Exception as e:
            logger.warning(f"Error fetching ticker from CryptoView API for {clean_exchange}:{clean_symbol}: {e}")

        # Fallback: fetch last 1m candle
        try:
            candles = await self.get_candles(symbol=clean_symbol, timeframe="1m", exchange=clean_exchange, limit=1)
            if candles:
                last_c = candles[-1]
                return {
                    "exchange": clean_exchange,
                    "symbol": clean_symbol,
                    "last_price": last_c.close,
                    "open": last_c.open,
                    "high": last_c.high,
                    "low": last_c.low,
                    "volume": last_c.volume,
                    "time": int(last_c.timestamp / 1000),
                }
        except Exception:
            pass

        return None

    async def close(self) -> None:
        """Closes any persistent resources."""
        pass
