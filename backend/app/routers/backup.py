import gzip
import json
from datetime import datetime, timezone
from typing import Dict, Any
from fastapi import APIRouter, Depends, Query, Response, Request, HTTPException

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
    y opcionalmente todas las velas históricas).
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
        "version": "1.0",
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

            # 5. Market Candles (opcional)
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

    return {
        "status": "ok",
        "message": "Respaldo restaurado exitosamente en la base de datos.",
        "restored_counts": restored_counts
    }
