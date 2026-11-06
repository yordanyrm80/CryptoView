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

            # Monitoreo de latidos de servicios 24/7 (collector y bot_supervisor)
            heartbeats_rows = await conn.fetch("""
                SELECT service_name, last_heartbeat, status, details,
                       EXTRACT(EPOCH FROM (NOW() - last_heartbeat)) AS seconds_since_heartbeat
                FROM system_heartbeat;
            """)

        hb_map = {r["service_name"]: r for r in heartbeats_rows}

        def _parse_service_hb(hb_row, max_seconds=90):
            if not hb_row:
                return "offline", None, {}
            sec = float(hb_row["seconds_since_heartbeat"] or 0)
            raw = hb_row["details"]
            det = json.loads(raw) if isinstance(raw, str) else (raw if isinstance(raw, dict) else {})
            stat = "online" if sec <= max_seconds else "stalled"
            return stat, round(sec, 1), det

        collector_status, collector_sec, collector_det = _parse_service_hb(hb_map.get("collector"), max_seconds=90)
        bot_sup_status, bot_sup_sec, bot_sup_det = _parse_service_hb(hb_map.get("bot_supervisor"), max_seconds=180)

        return {
            "status": "online",
            "database": "connected (TimescaleDB / PostgreSQL 17)",
            # Compatibilidad retroactiva con cliente Flutter existente
            "worker_status": collector_status,
            "worker_last_seen_seconds": collector_sec,
            "worker_details": collector_det,
            # Nueva telemetría independiente de Bot Supervisor
            "bot_supervisor_status": bot_sup_status,
            "bot_supervisor_last_seen_seconds": bot_sup_sec,
            "bot_supervisor_details": bot_sup_det,
            "services": {
                "collector": {
                    "status": collector_status,
                    "last_seen_seconds": collector_sec,
                    "details": collector_det,
                },
                "bot_supervisor": {
                    "status": bot_sup_status,
                    "last_seen_seconds": bot_sup_sec,
                    "details": bot_sup_det,
                },
            },
            "tracked_symbols_active": symbols_count or 0,
            "total_candles_stored": max(0, candles_count or 0),
            "total_trades_stored": trades_count or 0,
        }
    except Exception as e:
        return {
            "status": "degraded",
            "error": str(e)
        }
