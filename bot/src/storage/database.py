import logging
import os
from pathlib import Path
from typing import Optional, Union

import psycopg2
import psycopg2.extras
from psycopg2.pool import ThreadedConnectionPool

logger = logging.getLogger(__name__)

DEFAULT_DATABASE_URL = "postgresql://postgres:postgres@127.0.0.1:5432/criptobot"


class PostgresConnectionWrapper:
    """Managed connection wrapper providing DictCursor and automatic resource management."""

    def __init__(self, conn, pool: Optional[ThreadedConnectionPool] = None):
        self._conn = conn
        self._pool = pool
        self._closed = False

    def cursor(self):
        return self._conn.cursor(cursor_factory=psycopg2.extras.DictCursor)

    def execute(self, query: str, params=None):
        cur = self.cursor()
        cur.execute(query, params)
        return cur

    def commit(self):
        self._conn.commit()

    def rollback(self):
        self._conn.rollback()

    def close(self):
        if not self._closed:
            self._closed = True
            if self._pool is not None:
                try:
                    self._pool.putconn(self._conn)
                except Exception as e:
                    logger.debug(f"Error returning connection to pool: {e}")
            else:
                try:
                    self._conn.close()
                except Exception as e:
                    logger.debug(f"Error closing direct connection: {e}")

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        try:
            if exc_type is not None:
                self.rollback()
            else:
                self.commit()
        finally:
            self.close()


class DatabaseManager:
    """PostgreSQL database manager with connection pooling and schema initialization."""

    def __init__(self, connection_url: Optional[Union[Path, str]] = None):
        raw_url = str(connection_url) if connection_url is not None else ""
        if raw_url.startswith("postgresql://") or raw_url.startswith("postgres://"):
            self.connection_url = raw_url
        else:
            self.connection_url = os.getenv("DATABASE_URL", DEFAULT_DATABASE_URL)

        self.dialect = "postgres"
        try:
            self._pool = ThreadedConnectionPool(minconn=1, maxconn=20, dsn=self.connection_url)
        except Exception as e:
            logger.warning(f"Could not initialize connection pool: {e}")
            self._pool = None

        self._init_schema()

    def get_connection(self) -> PostgresConnectionWrapper:
        """Returns a managed PostgreSQL connection with DictCursor and health check."""
        if self._pool is not None:
            try:
                conn = self._pool.getconn()
                if conn.closed != 0:
                    self._pool.putconn(conn, close=True)
                    conn = self._pool.getconn()
                return PostgresConnectionWrapper(conn, pool=self._pool)
            except Exception as e:
                logger.warning(f"Connection pool checkout failed, falling back to direct connection: {e}")

        conn = psycopg2.connect(self.connection_url)
        return PostgresConnectionWrapper(conn, pool=None)

    def _init_schema(self) -> None:
        """Initializes database schema and indexes in PostgreSQL."""
        with self.get_connection() as conn:
            conn.execute("""
                CREATE TABLE IF NOT EXISTS candles (
                    symbol VARCHAR(32) NOT NULL,
                    timeframe VARCHAR(8) NOT NULL,
                    timestamp BIGINT NOT NULL,
                    open DOUBLE PRECISION NOT NULL,
                    high DOUBLE PRECISION NOT NULL,
                    low DOUBLE PRECISION NOT NULL,
                    close DOUBLE PRECISION NOT NULL,
                    volume DOUBLE PRECISION NOT NULL,
                    PRIMARY KEY (symbol, timeframe, timestamp)
                );
            """)
            conn.execute("""
                CREATE INDEX IF NOT EXISTS idx_candles_lookup 
                ON candles (symbol, timeframe, timestamp ASC);
            """)
            conn.execute("""
                CREATE TABLE IF NOT EXISTS bots (
                    bot_id VARCHAR(64) PRIMARY KEY,
                    symbol VARCHAR(32) NOT NULL,
                    strategy_name VARCHAR(64) NOT NULL,
                    budget DOUBLE PRECISION NOT NULL,
                    status VARCHAR(32) NOT NULL,
                    dry_run BOOLEAN NOT NULL DEFAULT TRUE,
                    config_json TEXT NOT NULL,
                    created_at BIGINT NOT NULL,
                    updated_at BIGINT NOT NULL
                );
            """)
            conn.execute("""
                CREATE INDEX IF NOT EXISTS idx_bots_status 
                ON bots (status);
            """)
            conn.execute("""
                CREATE TABLE IF NOT EXISTS orders (
                    id VARCHAR(64) PRIMARY KEY,
                    bot_id VARCHAR(64) NOT NULL,
                    symbol VARCHAR(32) NOT NULL,
                    side VARCHAR(16) NOT NULL,
                    order_type VARCHAR(16) NOT NULL,
                    price DOUBLE PRECISION NOT NULL,
                    amount DOUBLE PRECISION NOT NULL,
                    status VARCHAR(32) NOT NULL,
                    fee DOUBLE PRECISION DEFAULT 0.0,
                    created_at BIGINT NOT NULL,
                    filled_at BIGINT
                );
            """)
            conn.execute("""
                CREATE INDEX IF NOT EXISTS idx_orders_bot_status 
                ON orders (bot_id, status);
            """)
            conn.execute("""
                CREATE TABLE IF NOT EXISTS tranches (
                    id SERIAL PRIMARY KEY,
                    bot_id VARCHAR(64) NOT NULL,
                    symbol VARCHAR(32) NOT NULL,
                    tranche_index INTEGER NOT NULL,
                    allocated_budget DOUBLE PRECISION NOT NULL,
                    buy_price DOUBLE PRECISION NOT NULL,
                    amount DOUBLE PRECISION NOT NULL,
                    target_sell_price DOUBLE PRECISION NOT NULL,
                    actual_sell_price DOUBLE PRECISION,
                    status VARCHAR(32) NOT NULL,
                    buy_fee DOUBLE PRECISION DEFAULT 0.0,
                    sell_fee DOUBLE PRECISION DEFAULT 0.0,
                    buy_timestamp BIGINT,
                    sell_timestamp BIGINT,
                    profit_usdt DOUBLE PRECISION DEFAULT 0.0,
                    subsidized_satoshis DOUBLE PRECISION DEFAULT 0.0
                );
            """)
            conn.execute("""
                CREATE INDEX IF NOT EXISTS idx_tranches_lookup 
                ON tranches (bot_id, status);
            """)
            conn.execute("""
                CREATE TABLE IF NOT EXISTS capital_transactions (
                    id SERIAL PRIMARY KEY,
                    bot_id VARCHAR(64) NOT NULL,
                    type VARCHAR(32) NOT NULL,
                    amount DOUBLE PRECISION NOT NULL,
                    available_after DOUBLE PRECISION NOT NULL,
                    timestamp BIGINT NOT NULL,
                    reason TEXT,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                );
            """)
            conn.execute("""
                CREATE INDEX IF NOT EXISTS idx_capital_tx_lookup 
                ON capital_transactions (bot_id, timestamp ASC);
            """)
            conn.execute("""
                CREATE TABLE IF NOT EXISTS bot_events (
                    id SERIAL PRIMARY KEY,
                    bot_id VARCHAR(64) NOT NULL,
                    event_type VARCHAR(64) NOT NULL,
                    details TEXT,
                    timestamp BIGINT NOT NULL,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                );
            """)
            conn.execute("""
                CREATE INDEX IF NOT EXISTS idx_bot_events_lookup 
                ON bot_events (bot_id, timestamp ASC);
            """)
            conn.execute("""
                CREATE TABLE IF NOT EXISTS system_settings (
                    key VARCHAR(64) PRIMARY KEY,
                    value_json TEXT NOT NULL,
                    updated_at BIGINT NOT NULL
                );
            """)
