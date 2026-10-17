from fastapi import APIRouter, Query, HTTPException, Depends
from typing import List, Dict, Any
from pydantic import BaseModel
from app.database import get_db_pool
from app.auth import verify_api_key

router = APIRouter(
    prefix="/api/v1/symbols",
    tags=["Tracked Symbols"],
    dependencies=[Depends(verify_api_key)]
)

class TrackedSymbolCreate(BaseModel):
    exchange: str
    symbol: str

@router.get("", response_model=List[Dict[str, Any]])
async def list_tracked_symbols():
    """
    Lista las monedas en seguimiento junto con su estado de backfill histórico y rango de fechas almacenado.
    Utiliza escaneo indexado ultrarrápido para evitar bloquear la base de datos con escaneos secuenciales.
    """
    pool = await get_db_pool()
    query = """
        SELECT 
            ts.exchange,
            ts.symbol,
            ts.is_active,
            COALESCE(ts.backfill_completed, FALSE) AS backfill_completed,
            ts.created_at,
            (
                SELECT time 
                FROM market_candles mc 
                WHERE mc.exchange = ts.exchange AND mc.symbol = ts.symbol 
                ORDER BY mc.time ASC 
                LIMIT 1
            ) AS oldest_candle_utc,
            (
                SELECT time 
                FROM market_candles mc 
                WHERE mc.exchange = ts.exchange AND mc.symbol = ts.symbol 
                ORDER BY mc.time DESC 
                LIMIT 1
            ) AS latest_candle_utc
        FROM tracked_symbols ts
        ORDER BY ts.created_at DESC;
    """
    async with pool.acquire() as conn:
        rows = await conn.fetch(query)
    return [dict(r) for r in rows]

@router.post("", status_code=201, dependencies=[Depends(verify_api_key)])
async def add_tracked_symbol(payload: TrackedSymbolCreate):
    pool = await get_db_pool()
    ex = payload.exchange.lower().strip()
    sym = payload.symbol.replace('-', '/').upper().strip()

    query = """
        INSERT INTO tracked_symbols (exchange, symbol, is_active, backfill_completed)
        VALUES ($1, $2, TRUE, FALSE)
        ON CONFLICT (exchange, symbol) 
        DO UPDATE SET is_active = TRUE
        RETURNING exchange, symbol, is_active, backfill_completed;
    """
    async with pool.acquire() as conn:
        row = await conn.fetchrow(query, ex, sym)

    return {"status": "ok", "tracked": dict(row)}

@router.delete("", dependencies=[Depends(verify_api_key)])
async def remove_tracked_symbol(
    exchange: str = Query(...),
    symbol: str = Query(...),
):
    pool = await get_db_pool()
    ex = exchange.lower().strip()
    sym = symbol.replace('-', '/').upper().strip()

    query = """
        UPDATE tracked_symbols
        SET is_active = FALSE
        WHERE exchange = $1 AND symbol = $2
        RETURNING exchange, symbol, is_active, backfill_completed;
    """
    async with pool.acquire() as conn:
        row = await conn.fetchrow(query, ex, sym)

    if not row:
        raise HTTPException(status_code=404, detail="Símbolo no encontrado")

    return {"status": "ok", "disabled": dict(row)}
