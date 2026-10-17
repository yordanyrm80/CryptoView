from fastapi import APIRouter
from typing import Dict, Any
from app.database import get_db_pool

router = APIRouter(prefix="/api/v1/health", tags=["Health"])

@router.get("", response_model=Dict[str, Any])
async def health_check():
    pool = await get_db_pool()
    try:
        async with pool.acquire() as conn:
            candles_count = await conn.fetchval("SELECT COUNT(*) FROM market_candles;")
            symbols_count = await conn.fetchval("SELECT COUNT(*) FROM tracked_symbols WHERE is_active = TRUE;")
            trades_count = await conn.fetchval("SELECT COUNT(*) FROM account_trades;")

        return {
            "status": "online",
            "database": "connected (TimescaleDB / PostgreSQL 17)",
            "tracked_symbols_active": symbols_count,
            "total_candles_stored": candles_count,
            "total_trades_stored": trades_count,
        }
    except Exception as e:
        return {
            "status": "degraded",
            "error": str(e)
        }
