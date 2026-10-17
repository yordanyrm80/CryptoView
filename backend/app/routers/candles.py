from fastapi import APIRouter, Query, HTTPException
from typing import Optional, List, Dict, Any
from datetime import datetime
from app.database import get_db_pool

router = APIRouter(prefix="/api/v1/candles", tags=["Candles"])

# Vistas continuas precalculadas en TimescaleDB para máxima velocidad
CONTINUOUS_VIEWS = {
    "5m": "candles_5m",
    "1h": "candles_1h",
    "1d": "candles_1d",
}

# Intervalos calculables al vuelo con time_bucket
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

@router.get("", response_model=List[Dict[str, Any]])
async def get_candles(
    exchange: str = Query(..., description="Nombre del exchange (binance, kucoin)"),
    symbol: str = Query(..., description="Par de trading (BTC/USDT, BTC-USDT)"),
    interval: str = Query("1h", description="Intervalo (1m, 5m, 15m, 1h, 4h, 1d, etc.)"),
    limit: int = Query(500, ge=1, le=2000, description="Cantidad máxima de velas"),
    start_time: Optional[datetime] = Query(None, description="Fecha de inicio (ISO 8601)"),
    end_time: Optional[datetime] = Query(None, description="Fecha de fin (ISO 8601)"),
    auto_track: bool = Query(True, description="Registrar automáticamente este símbolo para ingestión 24/7 si no existía")
):
    pool = await get_db_pool()
    norm_symbol = symbol.replace('-', '/').upper()
    ex = exchange.lower().strip()
    norm_interval = interval.lower().strip()

    # Si auto_track está activado, asegurar que el par quede registrado en tracked_symbols
    if auto_track:
        async with pool.acquire() as conn:
            await conn.execute("""
                INSERT INTO tracked_symbols (exchange, symbol, is_active)
                VALUES ($1, $2, TRUE)
                ON CONFLICT (exchange, symbol) DO NOTHING;
            """, ex, norm_symbol)

    params = [ex, norm_symbol]

    # Caso 1: Velas base de 1 minuto (Hypertable directa)
    if norm_interval == "1m":
        query = "SELECT time, open, high, low, close, volume FROM market_candles WHERE exchange = $1 AND symbol = $2"
        if start_time:
            params.append(start_time)
            query += f" AND time >= ${len(params)}"
        if end_time:
            params.append(end_time)
            query += f" AND time <= ${len(params)}"
        params.append(limit)
        query += f" ORDER BY time DESC LIMIT ${len(params)}"

    # Caso 2: Vistas materializadas continuas de TimescaleDB (5m, 1h, 1d)
    elif norm_interval in CONTINUOUS_VIEWS:
        table_view = CONTINUOUS_VIEWS[norm_interval]
        query = f"SELECT time, open, high, low, close, volume FROM {table_view} WHERE exchange = $1 AND symbol = $2"
        if start_time:
            params.append(start_time)
            query += f" AND time >= ${len(params)}"
        if end_time:
            params.append(end_time)
            query += f" AND time <= ${len(params)}"
        params.append(limit)
        query += f" ORDER BY time DESC LIMIT ${len(params)}"

    # Caso 3: Agregación dinámica al vuelo con time_bucket
    else:
        bucket_duration = TIME_BUCKET_MAP.get(norm_interval, "1 hour")
        query = f"""
            SELECT
                time_bucket('{bucket_duration}', time) AS time,
                first(open, time) AS open,
                max(high) AS high,
                min(low) AS low,
                last(close, time) AS close,
                sum(volume) AS volume
            FROM market_candles
            WHERE exchange = $1 AND symbol = $2
        """
        if start_time:
            params.append(start_time)
            query += f" AND time >= ${len(params)}"
        if end_time:
            params.append(end_time)
            query += f" AND time <= ${len(params)}"
        params.append(limit)
        query += f" GROUP BY 1 ORDER BY 1 DESC LIMIT ${len(params)}"

    async with pool.acquire() as conn:
        rows = await conn.fetch(query, *params)

    # Devolver en orden cronológico ascendente (pasado -> presente)
    candles = [
        {
            "time": int(r["time"].timestamp()),
            "open": r["open"],
            "high": r["high"],
            "low": r["low"],
            "close": r["close"],
            "volume": r["volume"]
        }
        for r in reversed(rows)
    ]
    return candles
