import logging
import os
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional
import httpx
from src.domain.models import Candle

logger = logging.getLogger(__name__)

DEFAULT_API_URL = "https://129-146-110-196.sslip.io"
DEFAULT_API_KEY = "aa0d07ca7079caf19492d0fc4a762c593b3e02e205c669ae60de5cbbd66979c2"


class CryptoViewClient:
    """Institutional client for CryptoView Central Data Engine (TimescaleDB / PostgreSQL 17).
    
    Provides high-speed, 24/7 continuous historical and real-time candle data
    over HTTPS with GZip compression and zero exchange rate-limiting bottlenecks.
    """

    def __init__(
        self,
        base_url: Optional[str] = None,
        api_key: Optional[str] = None,
        timeout: float = 15.0,
    ):
        raw_url = base_url or os.getenv("CRYPTOVIEW_API_URL", DEFAULT_API_URL)
        self.base_url = raw_url.rstrip("/")
        self.api_key = api_key or os.getenv("CRYPTOVIEW_API_KEY", DEFAULT_API_KEY)
        self.timeout = timeout

    @property
    def headers(self) -> Dict[str, str]:
        return {
            "Accept": "application/json",
            "X-API-Key": self.api_key,
        }

    async def check_health(self) -> Dict[str, Any]:
        """Checks connectivity and telemetry status against /api/v1/health."""
        url = f"{self.base_url}/api/v1/health"
        async with httpx.AsyncClient(timeout=self.timeout) as client:
            resp = await client.get(url, headers=self.headers)
            resp.raise_for_status()
            return resp.json()

    async def fetch_candles(
        self,
        symbol: str,
        timeframe: str = "1h",
        exchange: str = "kucoin",
        limit: int = 500,
        start_time_ms: Optional[int] = None,
        end_time_ms: Optional[int] = None,
        auto_track: bool = True,
        max_retries: int = 3,
    ) -> List[Candle]:
        """Asynchronously fetches OHLCV candles from CryptoView TimescaleDB."""
        url = f"{self.base_url}/api/v1/candles"
        clean_symbol = symbol.replace("-", "/").upper()
        clean_exchange = exchange.lower().strip()
        safe_limit = max(1, min(limit, 2000))

        params: Dict[str, Any] = {
            "exchange": clean_exchange,
            "symbol": clean_symbol,
            "interval": timeframe.lower().strip(),
            "limit": safe_limit,
            "auto_track": "true" if auto_track else "false",
        }

        if start_time_ms is not None:
            start_iso = datetime.fromtimestamp(start_time_ms / 1000.0, tz=timezone.utc).isoformat()
            params["start_time"] = start_iso

        if end_time_ms is not None:
            end_iso = datetime.fromtimestamp(end_time_ms / 1000.0, tz=timezone.utc).isoformat()
            params["end_time"] = end_iso

        retries = 0
        backoff = 1.0

        while retries < max_retries:
            try:
                async with httpx.AsyncClient(timeout=self.timeout) as client:
                    resp = await client.get(url, params=params, headers=self.headers)
                    if resp.status_code == 200:
                        raw_data = resp.json()
                        return [
                            Candle(
                                symbol=clean_symbol,
                                timeframe=timeframe,
                                timestamp=int(c["time"] * 1000),  # Convert seconds to UTC milliseconds
                                open=float(c["open"]),
                                high=float(c["high"]),
                                low=float(c["low"]),
                                close=float(c["close"]),
                                volume=float(c["volume"]),
                            )
                            for c in raw_data
                        ]
                    elif resp.status_code == 404:
                        logger.warning(f"No candles found on CryptoView for {clean_exchange}:{clean_symbol}")
                        return []
                    else:
                        resp.raise_for_status()

            except (httpx.RequestError, httpx.HTTPStatusError) as e:
                retries += 1
                logger.warning(
                    f"CryptoView API error for {clean_symbol} ({e}). Retry {retries}/{max_retries} in {backoff:.1f}s..."
                )
                if retries >= max_retries:
                    raise
                import asyncio
                await asyncio.sleep(backoff)
                backoff *= 2.0

        return []

    def fetch_candles_sync(
        self,
        symbol: str,
        timeframe: str = "1h",
        exchange: str = "kucoin",
        limit: int = 500,
        start_time_ms: Optional[int] = None,
        end_time_ms: Optional[int] = None,
        auto_track: bool = True,
    ) -> List[Candle]:
        """Synchronous wrapper for scripts and non-async runners."""
        clean_symbol = symbol.replace("-", "/").upper()
        clean_exchange = exchange.lower().strip()
        url = f"{self.base_url}/api/v1/candles"
        safe_limit = max(1, min(limit, 2000))

        params: Dict[str, Any] = {
            "exchange": clean_exchange,
            "symbol": clean_symbol,
            "interval": timeframe.lower().strip(),
            "limit": safe_limit,
            "auto_track": "true" if auto_track else "false",
        }

        if start_time_ms is not None:
            start_iso = datetime.fromtimestamp(start_time_ms / 1000.0, tz=timezone.utc).isoformat()
            params["start_time"] = start_iso

        if end_time_ms is not None:
            end_iso = datetime.fromtimestamp(end_time_ms / 1000.0, tz=timezone.utc).isoformat()
            params["end_time"] = end_iso

        with httpx.Client(timeout=self.timeout) as client:
            resp = client.get(url, params=params, headers=self.headers)
            resp.raise_for_status()
            raw_data = resp.json()
            return [
                Candle(
                    symbol=clean_symbol,
                    timeframe=timeframe,
                    timestamp=int(c["time"] * 1000),
                    open=float(c["open"]),
                    high=float(c["high"]),
                    low=float(c["low"]),
                    close=float(c["close"]),
                    volume=float(c["volume"]),
                )
                for c in raw_data
            ]
