from fastapi import APIRouter, Depends
from typing import Dict, Any
from app.database import get_db_pool
from app.auth import verify_api_key

router = APIRouter(
    prefix="/api/v1/health",
    tags=["Health"],
    dependencies=[Depends(verify_api_key)]
)

@router.get("", response_model=Dict[str, Any])
async def health_check():
    pool = await get_db_pool()
    try:
        async with pool.acquire() as conn:
            # Estimación ultrarrápida (<1ms) para no escanear millones de filas en TimescaleDB
            candles_count = await conn.fetchval("""
                SELECT COALESCE(
                    NULLIF((SELECT reltuples::bigint FROM pg_class WHERE relname = 'market_candles'), -1),
                    (SELECT COUNT(*) FROM market_candles)
                );
            """)
            symbols_count = await conn.fetchval("SELECT COUNT(*) FROM tracked_symbols WHERE is_active = TRUE;")
            trades_count = await conn.fetchval("SELECT COUNT(*) FROM account_trades;")

        return {
            "status": "online",
            "database": "connected (TimescaleDB / PostgreSQL 17)",
            "tracked_symbols_active": symbols_count,
            "total_candles_stored": max(0, candles_count or 0),
            "total_trades_stored": trades_count or 0,
        }
    except Exception as e:
        return {
            "status": "degraded",
            "error": str(e)
        }
