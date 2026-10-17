import json
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

            # Monitoreo de latido del Ingestion Worker 24/7
            worker_hb = await conn.fetchrow("""
                SELECT last_heartbeat, status, details,
                       EXTRACT(EPOCH FROM (NOW() - last_heartbeat)) AS seconds_since_heartbeat
                FROM system_heartbeat
                WHERE service_name = 'collector';
            """)

        worker_status = "offline"
        seconds_ago = None
        details = {}

        if worker_hb:
            seconds_ago = float(worker_hb["seconds_since_heartbeat"] or 0)
            raw_details = worker_hb["details"]
            if isinstance(raw_details, str):
                try:
                    details = json.loads(raw_details)
                except Exception:
                    details = {}
            elif isinstance(raw_details, dict):
                details = raw_details

            # Si el worker reportó en los últimos 90 segundos se considera en línea
            if seconds_ago <= 90:
                worker_status = "online"
            else:
                worker_status = "stalled"

        return {
            "status": "online",
            "database": "connected (TimescaleDB / PostgreSQL 17)",
            "worker_status": worker_status,
            "worker_last_seen_seconds": round(seconds_ago, 1) if seconds_ago is not None else None,
            "worker_details": details,
            "tracked_symbols_active": symbols_count or 0,
            "total_candles_stored": max(0, candles_count or 0),
            "total_trades_stored": trades_count or 0,
        }
    except Exception as e:
        return {
            "status": "degraded",
            "error": str(e)
        }
