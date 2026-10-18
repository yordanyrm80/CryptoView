import os
import gzip
import json
import asyncio
from pathlib import Path
from datetime import datetime, timezone
from typing import Dict, Any, List
from fastapi import APIRouter, Depends, Query, Response, Request, HTTPException
from fastapi.responses import FileResponse

from app.database import get_db_pool
from app.auth import verify_api_key

router = APIRouter(
    prefix="/api/v1/backup",
    tags=["Database Backup & Restore"],
    dependencies=[Depends(verify_api_key)]
)

def _serialize_row(row) -> Dict[str, Any]:
    d = dict(row)
    for k, v in d.items():
        if isinstance(v, datetime):
            d[k] = v.astimezone(timezone.utc).isoformat()
    return d

@router.get("/export")
async def export_database_backup(
    include_candles: bool = Query(False, description="Si es True incluye todas las velas de 1m de market_candles"),
    compressed: bool = Query(True, description="Si es True devuelve un archivo .json.gz comprimido")
):
    """
    Genera una salva completa de las tablas del servidor (símbolos, API keys cifradas, trades, retiros, casamientos
    y opcionalmente todas las velas históricas) para descargarla a la PC del usuario.
    """
    pool = await get_db_pool()
    now_utc = datetime.now(timezone.utc)

    async with pool.acquire() as conn:
        symbols = [_serialize_row(r) for r in await conn.fetch("SELECT * FROM tracked_symbols ORDER BY exchange, symbol;")]
        keys = [_serialize_row(r) for r in await conn.fetch("SELECT * FROM api_keys ORDER BY exchange;")]
        trades = [_serialize_row(r) for r in await conn.fetch("SELECT * FROM account_trades ORDER BY id ASC;")]
        withdrawals = [_serialize_row(r) for r in await conn.fetch("SELECT * FROM account_withdrawals ORDER BY id ASC;")]
        matches = [_serialize_row(r) for r in await conn.fetch("SELECT * FROM trade_matches ORDER BY id ASC;")]

        candles = []
        if include_candles:
            candle_rows = await conn.fetch("SELECT time, exchange, symbol, open, high, low, close, volume FROM market_candles ORDER BY time ASC;")
            candles = [
                [
                    int(r["time"].timestamp()),
                    r["exchange"],
                    r["symbol"],
                    r["open"],
                    r["high"],
                    r["low"],
                    r["close"],
                    r["volume"],
                ]
                for r in candle_rows
            ]

    backup_payload = {
        "version": "2.0",
        "exported_at_utc": now_utc.isoformat(),
        "include_candles": include_candles,
        "counts": {
            "tracked_symbols": len(symbols),
            "api_keys": len(keys),
            "account_trades": len(trades),
            "account_withdrawals": len(withdrawals),
            "trade_matches": len(matches),
            "market_candles": len(candles),
        },
        "data": {
            "tracked_symbols": symbols,
            "api_keys": keys,
            "account_trades": trades,
            "account_withdrawals": withdrawals,
            "trade_matches": matches,
            "market_candles": candles,
        }
    }

    timestamp_str = now_utc.strftime("%Y-%m-%d_%H-%M-%S")
    json_bytes = json.dumps(backup_payload, ensure_ascii=False).encode("utf-8")

    if compressed:
        gz_bytes = gzip.compress(json_bytes, compresslevel=9)
        filename = f"cryptoview_cloud_backup_{timestamp_str}.json.gz"
        return Response(
            content=gz_bytes,
            media_type="application/gzip",
            headers={
                "Content-Disposition": f'attachment; filename="{filename}"'
            }
        )

    filename = f"cryptoview_cloud_backup_{timestamp_str}.json"
    return Response(
        content=json_bytes,
        media_type="application/json",
        headers={
            "Content-Disposition": f'attachment; filename="{filename}"'
        }
    )

@router.post("/restore")
async def restore_database_backup(request: Request):
    """
    Restaura una salva (.json o .json.gz) previamente descargada desde /api/v1/backup/export.
    """
    raw_body = await request.body()
    if not raw_body:
        raise HTTPException(status_code=400, detail="Cuerpo de respaldo vacío.")

    try:
        # Detectar si viene comprimido con GZIP (magic bytes 1f 8b)
        if len(raw_body) >= 2 and raw_body[0] == 0x1F and raw_body[1] == 0x8B:
            raw_body = gzip.decompress(raw_body)
        payload = json.loads(raw_body.decode("utf-8"))
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Formato de archivo de respaldo inválido: {e}")

    data = payload.get("data", {})
    pool = await get_db_pool()
    restored_counts: Dict[str, int] = {}

    async with pool.acquire() as conn:
        async with conn.transaction():
            # 1. Tracked Symbols
            symbols = data.get("tracked_symbols", [])
            for s in symbols:
                await conn.execute("""
                    INSERT INTO tracked_symbols (exchange, symbol, is_active, backfill_completed)
                    VALUES ($1, $2, $3, $4)
                    ON CONFLICT (exchange, symbol) DO UPDATE SET
                        is_active = EXCLUDED.is_active,
                        backfill_completed = EXCLUDED.backfill_completed;
                """, s["exchange"], s["symbol"], s.get("is_active", True), s.get("backfill_completed", False))
            restored_counts["tracked_symbols"] = len(symbols)

            # 2. API Keys (cifradas)
            keys = data.get("api_keys", [])
            for k in keys:
                await conn.execute("""
                    INSERT INTO api_keys (exchange, api_key_encrypted, api_secret_encrypted, api_passphrase_encrypted, is_active)
                    VALUES ($1, $2, $3, $4, $5)
                    ON CONFLICT (exchange) DO UPDATE SET
                        api_key_encrypted = EXCLUDED.api_key_encrypted,
                        api_secret_encrypted = EXCLUDED.api_secret_encrypted,
                        api_passphrase_encrypted = EXCLUDED.api_passphrase_encrypted,
                        is_active = EXCLUDED.is_active,
                        updated_at = NOW();
                """, k["exchange"], k["api_key_encrypted"], k["api_secret_encrypted"], k.get("api_passphrase_encrypted", ""), k.get("is_active", True))
            restored_counts["api_keys"] = len(keys)

            # 3. Account Trades
            trades = data.get("account_trades", [])
            for t in trades:
                t_time = datetime.fromisoformat(t["time"])
                await conn.execute("""
                    INSERT INTO account_trades (trade_id, order_id, exchange, symbol, side, price, amount, fee, fee_currency, time, is_matched, remaining_amount, notes)
                    VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13)
                    ON CONFLICT (exchange, trade_id) DO UPDATE SET
                        is_matched = EXCLUDED.is_matched,
                        remaining_amount = EXCLUDED.remaining_amount,
                        notes = EXCLUDED.notes;
                """, t["trade_id"], t.get("order_id"), t["exchange"], t["symbol"], t["side"], float(t["price"]), float(t["amount"]), float(t.get("fee", 0.0)), t.get("fee_currency", "USDT"), t_time, t.get("is_matched", False), float(t.get("remaining_amount", t["amount"])), t.get("notes", ""))
            restored_counts["account_trades"] = len(trades)

            # 4. Account Withdrawals
            withdrawals = data.get("account_withdrawals", [])
            for w in withdrawals:
                w_time = datetime.fromisoformat(w["time"])
                await conn.execute("""
                    INSERT INTO account_withdrawals (exchange, currency, amount, fee, time, category, description, tx_id, is_matched)
                    VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
                    ON CONFLICT (exchange, tx_id, time) DO UPDATE SET
                        category = EXCLUDED.category,
                        description = EXCLUDED.description,
                        is_matched = EXCLUDED.is_matched;
                """, w["exchange"], w["currency"], float(w["amount"]), float(w.get("fee", 0.0)), w_time, w.get("category", "Gasto Personal"), w.get("description"), w.get("tx_id"), w.get("is_matched", False))
            restored_counts["account_withdrawals"] = len(withdrawals)

            # 5. Trade Matches
            matches = data.get("trade_matches", [])
            for m in matches:
                m_time = datetime.fromisoformat(m["time"])
                await conn.execute("""
                    INSERT INTO trade_matches (id, buy_trade_id, sell_trade_id, withdrawal_id, match_type, matched_amount, profit, time, notes)
                    VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
                    ON CONFLICT (id) DO UPDATE SET
                        matched_amount = EXCLUDED.matched_amount,
                        profit = EXCLUDED.profit,
                        notes = EXCLUDED.notes;
                """, int(m["id"]), m.get("buy_trade_id"), m.get("sell_trade_id"), m.get("withdrawal_id"), m.get("match_type", "trade"), float(m["matched_amount"]), float(m.get("profit", 0.0)), m_time, m.get("notes", ""))
            restored_counts["trade_matches"] = len(matches)

            # 6. Market Candles (opcional)
            candles = data.get("market_candles", [])
            if candles:
                records = [
                    (datetime.fromtimestamp(c[0], tz=timezone.utc), c[1], c[2], float(c[3]), float(c[4]), float(c[5]), float(c[6]), float(c[7]))
                    for c in candles
                ]
                await conn.executemany("""
                    INSERT INTO market_candles (time, exchange, symbol, open, high, low, close, volume)
                    VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
                    ON CONFLICT (time, exchange, symbol) DO NOTHING;
                """, records)
            restored_counts["market_candles"] = len(candles)

            # 7. Sincronizar secuencias serial (auto-increment) de PostgreSQL para evitar colisiones de ID
            await conn.execute("""
                SELECT setval(pg_get_serial_sequence('account_trades', 'id'), COALESCE((SELECT MAX(id) FROM account_trades), 1));
                SELECT setval(pg_get_serial_sequence('account_withdrawals', 'id'), COALESCE((SELECT MAX(id) FROM account_withdrawals), 1));
                SELECT setval(pg_get_serial_sequence('trade_matches', 'id'), COALESCE((SELECT MAX(id) FROM trade_matches), 1));
            """)

    return {
        "status": "ok",
        "message": "Respaldo restaurado exitosamente en la base de datos.",
        "restored_counts": restored_counts,
    }


# =========================================================================
# VOLCADO COMPLETO NATIVO TIMESCALEDB (PG_DUMP + GZIP STREAMING)
# =========================================================================

BACKUPS_DIR = Path("/app/backups")
if not BACKUPS_DIR.exists():
    try:
        BACKUPS_DIR.mkdir(parents=True, exist_ok=True)
    except Exception:
        BACKUPS_DIR = Path("./backups")
        BACKUPS_DIR.mkdir(parents=True, exist_ok=True)

_dump_lock = asyncio.Lock()
_current_dump_status: Dict[str, Any] = {
    "is_running": False,
    "started_at": None,
    "elapsed_seconds": 0,
    "last_error": None,
    "last_completed_file": None,
}


async def _execute_pg_dump_async(filename: str):
    global _current_dump_status
    filepath = BACKUPS_DIR / filename
    temp_filepath = BACKUPS_DIR / f"{filename}.tmp"

    db_user = os.getenv("POSTGRES_USER", "cryptoview")
    db_pass = os.getenv("POSTGRES_PASSWORD", "cryptoview_secure_pwd")
    db_name = os.getenv("POSTGRES_DB", "cryptoview_db")
    db_host = os.getenv("POSTGRES_HOST", "timescaledb" if os.path.exists("/.dockerenv") else "127.0.0.1")
    db_port = os.getenv("POSTGRES_PORT", "5432")

    env = os.environ.copy()
    env["PGPASSWORD"] = db_pass

    cmd = (
        f"pg_dump -h {db_host} -p {db_port} -U {db_user} -d {db_name} "
        f"--no-owner --no-privileges | gzip -9 > \"{temp_filepath}\""
    )

    try:
        process = await asyncio.create_subprocess_shell(
            cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
            env=env
        )
        stdout, stderr = await process.communicate()

        if process.returncode == 0 and temp_filepath.exists() and temp_filepath.stat().st_size > 0:
            if filepath.exists():
                filepath.unlink()
            temp_filepath.rename(filepath)
            _current_dump_status["last_completed_file"] = filename
            _current_dump_status["last_error"] = None
        else:
            err = stderr.decode() if stderr else f"Exit code {process.returncode}"
            _current_dump_status["last_error"] = err
            if temp_filepath.exists():
                temp_filepath.unlink()
    except Exception as e:
        _current_dump_status["last_error"] = str(e)
        if temp_filepath.exists():
            try:
                temp_filepath.unlink()
            except Exception:
                pass
    finally:
        _current_dump_status["is_running"] = False


@router.post("/pg_dump/create")
async def create_pg_dump():
    """
    Inicia la generación asíncrona del volcado nativo (.sql.gz) de TimescaleDB
    con todas las tablas y los más de 7.5 millones de velas sin bloquear memoria ni generar timeouts.
    """
    global _current_dump_status
    if _current_dump_status["is_running"]:
        return {
            "status": "already_running",
            "message": "Ya hay una tarea de volcado completo en ejecución.",
            "started_at": _current_dump_status["started_at"].isoformat() if _current_dump_status["started_at"] else None,
        }

    now_utc = datetime.now(timezone.utc)
    timestamp_str = now_utc.strftime("%Y-%m-%d_%H-%M-%S")
    filename = f"cryptoview_timescaledb_full_{timestamp_str}.sql.gz"

    _current_dump_status["is_running"] = True
    _current_dump_status["started_at"] = now_utc
    _current_dump_status["elapsed_seconds"] = 0
    _current_dump_status["last_error"] = None

    asyncio.create_task(_execute_pg_dump_async(filename))

    return {
        "status": "started",
        "filename": filename,
        "message": "Generando volcado nativo de TimescaleDB en el servidor...",
        "started_at": now_utc.isoformat(),
    }


@router.get("/pg_dump/status")
async def get_pg_dump_status():
    """
    Consulta el estado de generación y la lista de volcados .sql.gz disponibles en el servidor.
    """
    dumps = []
    if BACKUPS_DIR.exists():
        for f in BACKUPS_DIR.glob("*.sql.gz"):
            stat = f.stat()
            dumps.append({
                "filename": f.name,
                "size_bytes": stat.st_size,
                "size_mb": round(stat.st_size / (1024 * 1024), 2),
                "created_at_utc": datetime.fromtimestamp(stat.st_mtime, tz=timezone.utc).isoformat(),
            })
    dumps.sort(key=lambda x: x["created_at_utc"], reverse=True)

    status_data = dict(_current_dump_status)
    if status_data["is_running"] and status_data["started_at"]:
        status_data["elapsed_seconds"] = int((datetime.now(timezone.utc) - status_data["started_at"]).total_seconds())
    if status_data["started_at"]:
        status_data["started_at"] = status_data["started_at"].isoformat()

    return {
        "is_running": status_data["is_running"],
        "elapsed_seconds": status_data.get("elapsed_seconds", 0),
        "last_completed_file": status_data.get("last_completed_file"),
        "last_error": status_data.get("last_error"),
        "available_dumps": dumps,
    }


@router.get("/pg_dump/download/{filename}")
async def download_pg_dump_file(filename: str):
    """
    Descarga por streaming con cabecera Content-Length el archivo .sql.gz generado.
    """
    safe_name = os.path.basename(filename)
    filepath = BACKUPS_DIR / safe_name

    if not filepath.exists() or not filepath.is_file():
        raise HTTPException(status_code=404, detail="Archivo de volcado no encontrado en el servidor.")

    file_size = filepath.stat().st_size
    return FileResponse(
        path=str(filepath),
        filename=safe_name,
        media_type="application/gzip",
        headers={
            "Content-Length": str(file_size),
            "Content-Disposition": f'attachment; filename="{safe_name}"'
        }
    )


@router.delete("/pg_dump/{filename}")
async def delete_pg_dump_file(filename: str):
    """
    Elimina un archivo .sql.gz del servidor para liberar almacenamiento.
    """
    safe_name = os.path.basename(filename)
    filepath = BACKUPS_DIR / safe_name

    if filepath.exists() and filepath.is_file():
        filepath.unlink()
        return {"status": "ok", "message": f"Archivo {safe_name} eliminado del servidor."}

    raise HTTPException(status_code=404, detail="Archivo no encontrado.")


