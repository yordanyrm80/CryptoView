from typing import List, Optional
import pandas as pd
from src.domain.models import Candle
from src.storage.database import DatabaseManager


class CandleRepository:
    """Repository for storing and querying OHLCV candles in PostgreSQL."""

    def __init__(self, db_manager: DatabaseManager):
        self.db_manager = db_manager

    def save_candles(self, candles: List[Candle]) -> int:
        """Stores a batch of candles, ignoring duplicates."""
        if not candles:
            return 0

        query = """
            INSERT INTO candles 
            (symbol, timeframe, timestamp, open, high, low, close, volume)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
            ON CONFLICT (symbol, timeframe, timestamp) DO NOTHING;
        """
        records = [
            (
                c.symbol,
                c.timeframe,
                c.timestamp,
                c.open,
                c.high,
                c.low,
                c.close,
                c.volume,
            )
            for c in candles
        ]

        with self.db_manager.get_connection() as conn:
            cursor = conn.cursor()
            cursor.executemany(query, records)
            conn.commit()
            return cursor.rowcount if cursor.rowcount > 0 else len(records)

    def get_candles(
        self,
        symbol: str,
        timeframe: str,
        start_time: Optional[int] = None,
        end_time: Optional[int] = None,
        limit: Optional[int] = None,
    ) -> List[Candle]:
        """Retrieves candles ordered chronologically."""
        if start_time is None and limit is not None:
            query = """
                SELECT * FROM (
                    SELECT * FROM candles WHERE symbol = %s AND timeframe = %s
            """
            params = [symbol, timeframe]
            if end_time is not None:
                query += " AND timestamp <= %s"
                params.append(end_time)
            query += " ORDER BY timestamp DESC LIMIT %s) sub ORDER BY timestamp ASC"
            params.append(limit)
        else:
            query = "SELECT * FROM candles WHERE symbol = %s AND timeframe = %s"
            params = [symbol, timeframe]
            if start_time is not None:
                query += " AND timestamp >= %s"
                params.append(start_time)
            if end_time is not None:
                query += " AND timestamp <= %s"
                params.append(end_time)
            query += " ORDER BY timestamp ASC"
            if limit is not None:
                query += " LIMIT %s"
                params.append(limit)

        with self.db_manager.get_connection() as conn:
            rows = conn.execute(query, params).fetchall()
            return [
                Candle(
                    symbol=r["symbol"],
                    timeframe=r["timeframe"],
                    timestamp=r["timestamp"],
                    open=r["open"],
                    high=r["high"],
                    low=r["low"],
                    close=r["close"],
                    volume=r["volume"],
                )
                for r in rows
            ]

    def get_candles_df(
        self,
        symbol: str,
        timeframe: str,
        start_time: Optional[int] = None,
        end_time: Optional[int] = None,
        limit: Optional[int] = None,
    ) -> pd.DataFrame:
        """Retrieves candles directly as a Pandas DataFrame indexed by DatetimeIndex (UTC)."""
        candles = self.get_candles(
            symbol=symbol,
            timeframe=timeframe,
            start_time=start_time,
            end_time=end_time,
            limit=limit,
        )
        if not candles:
            return pd.DataFrame(
                columns=["timestamp", "open", "high", "low", "close", "volume"]
            )

        data = [
            {
                "timestamp": c.timestamp,
                "open": c.open,
                "high": c.high,
                "low": c.low,
                "close": c.close,
                "volume": c.volume,
            }
            for c in candles
        ]
        df = pd.DataFrame(data)
        df["dt"] = pd.to_datetime(df["timestamp"], unit="ms", utc=True)
        df.set_index("dt", inplace=True)
        return df

    def get_latest_timestamp(self, symbol: str, timeframe: str) -> Optional[int]:
        """Returns latest timestamp stored for a symbol and timeframe."""
        query = """
            SELECT MAX(timestamp) as max_ts 
            FROM candles 
            WHERE symbol = %s AND timeframe = %s;
        """
        with self.db_manager.get_connection() as conn:
            row = conn.execute(query, [symbol, timeframe]).fetchone()
            if row and row["max_ts"] is not None:
                return int(row["max_ts"])
            return None

    def get_earliest_timestamp(self, symbol: str, timeframe: str) -> Optional[int]:
        """Returns earliest timestamp stored for a symbol and timeframe."""
        query = """
            SELECT MIN(timestamp) as min_ts 
            FROM candles 
            WHERE symbol = %s AND timeframe = %s;
        """
        with self.db_manager.get_connection() as conn:
            row = conn.execute(query, [symbol, timeframe]).fetchone()
            if row and row["min_ts"] is not None:
                return int(row["min_ts"])
            return None

    def count_candles(self, symbol: str, timeframe: str) -> int:
        """Returns the total number of stored candles for a symbol and timeframe."""
        query = """
            SELECT COUNT(*) as count 
            FROM candles 
            WHERE symbol = %s AND timeframe = %s;
        """
        with self.db_manager.get_connection() as conn:
            row = conn.execute(query, [symbol, timeframe]).fetchone()
            if row and row["count"] is not None:
                return int(row["count"])
            return 0

