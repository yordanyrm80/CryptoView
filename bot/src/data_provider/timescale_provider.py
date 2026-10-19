import asyncio
import logging
import os
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional
import psycopg2
import psycopg2.extras
from psycopg2.pool import ThreadedConnectionPool
from src.data_provider.base import MarketDataProvider
from src.domain.models import Candle

logger = logging.getLogger("criptobot.data_provider.timescale")

CONTINUOUS_VIEWS = {
    "5m": "candles_5m",
    "1h": "candles_1h",
    "1d": "candles_1d",
}

TIME_BUCKET_MAP = {
    "3m": "3 minutes",
    "15m": "15 minutes",
    "30m": "30 minutes",
    "2h": "2 hours",
    "4h": "4 hours",
    "6h": "6 hours",
    "12h": "12 hours",
    "1w": "1 week",
}


class TimescaleMarketDataProvider(MarketDataProvider):
    """Direct PostgreSQL / TimescaleDB market data provider.
    
    Used when the bot is deployed on the same server as the CryptoView TimescaleDB engine.
    Queries the TimescaleDB hypertables and continuous aggregates directly via SQL
    with ultra-low latency (<1ms) and zero HTTP overhead.
    """

    def __init__(self, connection_url: Optional[str] = None):
        self.connection_url = connection_url or os.getenv(
            "TIMESCALE_DATABASE_URL",
            os.getenv("DATABASE_URL", "postgresql://cryptoview:cryptoview_secure_pwd@timescaledb:5432/cryptoview_db"),
        )
        try:
            self._pool = ThreadedConnectionPool(minconn=1, maxconn=10, dsn=self.connection_url)
            logger.info("TimescaleMarketDataProvider initialized with connection pool.")
        except Exception as e:
            logger.warning(f"TimescaleMarketDataProvider pool initialization failed, will use direct connect: {e}")
            self._pool = None

    def _get_connection(self):
        if self._pool is not None:
            try:
                conn = self._pool.getconn()
                if conn.closed != 0:
                    self._pool.putconn(conn, close=True)
                    conn = self._pool.getconn()
                return conn
            except Exception as e:
                logger.warning(f"Timescale pool checkout error ({e}), falling back to direct connection.")
        return psycopg2.connect(self.connection_url)

    def _release_connection(self, conn) -> None:
        if self._pool is not None:
            try:
                self._pool.putconn(conn)
                return
            except Exception:
                pass
        try:
            conn.close()
        except Exception:
            pass

    def get_candles_sync(
        self,
        symbol: str,
        timeframe: str = "1h",
        exchange: str = "kucoin",
        limit: int = 500,
        start_time_ms: Optional[int] = None,
        end_time_ms: Optional[int] = None,
    ) -> List[Candle]:
        """Synchronously retrieves OHLCV candles directly from TimescaleDB."""
        clean_symbol = symbol.replace("-", "/").upper()
        clean_exchange = exchange.lower().strip()
        clean_tf = timeframe.lower().strip()
        safe_limit = max(1, min(limit, 2000))

        conn = self._get_connection()
        try:
            with conn.cursor(cursor_factory=psycopg2.extras.DictCursor) as cur:
                params: List[Any] = [clean_exchange, clean_symbol]

                # 1. Continuous aggregate view or base 1m table
                if clean_tf in CONTINUOUS_VIEWS:
                    table_name = CONTINUOUS_VIEWS[clean_tf]
                    base_query = f"SELECT time, open, high, low, close, volume FROM {table_name} WHERE exchange = %s AND symbol = %s"
                    if start_time_ms is not None:
                        start_dt = datetime.fromtimestamp(start_time_ms / 1000.0, tz=timezone.utc)
                        base_query += " AND time >= %s"
                        params.append(start_dt)
                    if end_time_ms is not None:
                        end_dt = datetime.fromtimestamp(end_time_ms / 1000.0, tz=timezone.utc)
                        base_query += " AND time <= %s"
                        params.append(end_dt)
                    query = f"SELECT * FROM ({base_query} ORDER BY time DESC LIMIT %s) sub ORDER BY time ASC"
                    params.append(safe_limit)

                elif clean_tf == "1m":
                    base_query = "SELECT time, open, high, low, close, volume FROM market_candles WHERE exchange = %s AND symbol = %s"
                    if start_time_ms is not None:
                        start_dt = datetime.fromtimestamp(start_time_ms / 1000.0, tz=timezone.utc)
                        base_query += " AND time >= %s"
                        params.append(start_dt)
                    if end_time_ms is not None:
                        end_dt = datetime.fromtimestamp(end_time_ms / 1000.0, tz=timezone.utc)
                        base_query += " AND time <= %s"
                        params.append(end_dt)
                    query = f"SELECT * FROM ({base_query} ORDER BY time DESC LIMIT %s) sub ORDER BY time ASC"
                    params.append(safe_limit)

                elif clean_tf in TIME_BUCKET_MAP:
                    interval_str = TIME_BUCKET_MAP[clean_tf]
                    base_query = f"""
                        SELECT
                            time_bucket('{interval_str}', time) AS time,
                            first(open, time) AS open,
                            max(high) AS high,
                            min(low) AS low,
                            last(close, time) AS close,
                            sum(volume) AS volume
                        FROM market_candles
                        WHERE exchange = %s AND symbol = %s
                    """
                    if start_time_ms is not None:
                        start_dt = datetime.fromtimestamp(start_time_ms / 1000.0, tz=timezone.utc)
                        base_query += " AND time >= %s"
                        params.append(start_dt)
                    if end_time_ms is not None:
                        end_dt = datetime.fromtimestamp(end_time_ms / 1000.0, tz=timezone.utc)
                        base_query += " AND time <= %s"
                        params.append(end_dt)
                    base_query += f" GROUP BY time_bucket('{interval_str}', time)"
                    query = f"SELECT * FROM ({base_query} ORDER BY time DESC LIMIT %s) sub ORDER BY time ASC"
                    params.append(safe_limit)

                else:
                    logger.warning(f"Unsupported timeframe '{clean_tf}', falling back to 1h view.")
                    query = "SELECT * FROM (SELECT time, open, high, low, close, volume FROM candles_1h WHERE exchange = %s AND symbol = %s ORDER BY time DESC LIMIT %s) sub ORDER BY time ASC"
                    params = [clean_exchange, clean_symbol, safe_limit]

                cur.execute(query, params)
                rows = cur.fetchall()

                return [
                    Candle(
                        symbol=clean_symbol,
                        timeframe=clean_tf,
                        timestamp=int(r["time"].timestamp() * 1000),
                        open=float(r["open"]),
                        high=float(r["high"]),
                        low=float(r["low"]),
                        close=float(r["close"]),
                        volume=float(r["volume"] or 0.0),
                    )
                    for r in rows
                    if r["close"] is not None
                ]
        except Exception as e:
            logger.error(f"Error querying TimescaleDB for {clean_exchange}:{clean_symbol} ({clean_tf}): {e}")
            return []
        finally:
            self._release_connection(conn)

    async def get_candles(
        self,
        symbol: str,
        timeframe: str = "1h",
        exchange: str = "kucoin",
        limit: int = 500,
        start_time_ms: Optional[int] = None,
        end_time_ms: Optional[int] = None,
    ) -> List[Candle]:
        """Asynchronously executes TimescaleDB queries without blocking the event loop."""
        return await asyncio.to_thread(
            self.get_candles_sync,
            symbol=symbol,
            timeframe=timeframe,
            exchange=exchange,
            limit=limit,
            start_time_ms=start_time_ms,
            end_time_ms=end_time_ms,
        )

    async def get_ticker(
        self,
        symbol: str,
        exchange: str = "kucoin",
    ) -> Optional[Dict[str, Any]]:
        """Asynchronously fetches the latest live candle/ticker from TimescaleDB."""
        clean_symbol = symbol.replace("-", "/").upper()
        clean_exchange = exchange.lower().strip()

        def _fetch():
            conn = self._get_connection()
            try:
                with conn.cursor(cursor_factory=psycopg2.extras.DictCursor) as cur:
                    query = """
                        SELECT time, open, high, low, close, volume
                        FROM market_candles
                        WHERE exchange = %s AND symbol = %s
                        ORDER BY time DESC
                        LIMIT 1;
                    """
                    cur.execute(query, [clean_exchange, clean_symbol])
                    r = cur.fetchone()
                    if r:
                        return {
                            "exchange": clean_exchange,
                            "symbol": clean_symbol,
                            "last_price": float(r["close"]),
                            "open": float(r["open"]),
                            "high": float(r["high"]),
                            "low": float(r["low"]),
                            "volume": float(r["volume"] or 0.0),
                            "time": int(r["time"].timestamp()),
                        }
                    return None
            except Exception as e:
                logger.error(f"Error fetching ticker from TimescaleDB for {clean_exchange}:{clean_symbol}: {e}")
                return None
            finally:
                self._release_connection(conn)

        return await asyncio.to_thread(_fetch)

    async def close(self) -> None:
        """Closes the connection pool."""
        if self._pool is not None:
            try:
                self._pool.closeall()
                logger.info("TimescaleMarketDataProvider connection pool closed.")
            except Exception as e:
                logger.debug(f"Error closing Timescale pool: {e}")
