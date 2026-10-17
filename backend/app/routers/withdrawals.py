from fastapi import APIRouter, Query, HTTPException, Body, Depends, Path
from typing import Optional, List, Dict, Any
from datetime import datetime, timezone, timedelta
from pydantic import BaseModel, Field
import ccxt.async_support as ccxt

from app.database import get_db_pool
from app.auth import verify_api_key
from app.services.crypto import decrypt_secret

router = APIRouter(
    prefix="/api/v1/withdrawals",
    tags=["Withdrawals & Expenses"],
    dependencies=[Depends(verify_api_key)]
)

class WithdrawalCreate(BaseModel):
    exchange: str
    currency: str
    amount: float
    fee: float = 0.0
    time: datetime
    category: Optional[str] = "Gasto Personal"
    description: Optional[str] = ""
    tx_id: Optional[str] = ""
    is_matched: bool = False

class WithdrawalUpdate(BaseModel):
    is_matched: Optional[bool] = None
    category: Optional[str] = None
    description: Optional[str] = None

@router.get("", response_model=List[Dict[str, Any]])
async def get_withdrawals(
    exchange: Optional[str] = None,
    currency: Optional[str] = None,
    only_unmatched: bool = Query(False, description="Solo gastos no casados"),
    limit: int = Query(100, ge=1, le=1000),
):
    pool = await get_db_pool()
    query = "SELECT * FROM account_withdrawals WHERE 1=1"
    params = []

    if exchange:
        params.append(exchange.lower().strip())
        query += f" AND exchange = ${len(params)}"

    if currency:
        params.append(currency.upper().strip())
        query += f" AND currency = ${len(params)}"

    if only_unmatched:
        query += " AND is_matched = FALSE"

    params.append(limit)
    query += f" ORDER BY time DESC LIMIT ${len(params)}"

    async with pool.acquire() as conn:
        rows = await conn.fetch(query, *params)

    return [dict(r) for r in rows]

@router.post("", status_code=201)
async def create_withdrawal(payload: WithdrawalCreate):
    pool = await get_db_pool()
    query = """
        INSERT INTO account_withdrawals (exchange, currency, amount, fee, time, category, description, tx_id, is_matched)
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
        ON CONFLICT (exchange, tx_id, time) DO NOTHING
        RETURNING id;
    """
    async with pool.acquire() as conn:
        row_id = await conn.fetchval(
            query,
            payload.exchange.lower().strip(),
            payload.currency.upper().strip(),
            payload.amount,
            payload.fee,
            payload.time,
            payload.category or "Gasto Personal",
            payload.description or "",
            payload.tx_id or "",
            payload.is_matched,
        )
    return {"status": "ok", "id": row_id}

@router.post("/sync")
async def sync_withdrawals_from_exchange(
    exchange: str = Query(..., description="Nombre del exchange (kucoin, binance)"),
    currency: Optional[str] = Query(None, description="Criptomoneda específica (ej. USDT)"),
    days: int = Query(30, ge=1, le=730, description="Días hacia atrás a consultar")
):
    ex_name = exchange.lower().strip()
    pool = await get_db_pool()

    async with pool.acquire() as conn:
        cred = await conn.fetchrow("""
            SELECT api_key_encrypted, api_secret_encrypted, api_passphrase_encrypted
            FROM api_keys
            WHERE exchange = $1 AND is_active = TRUE;
        """, ex_name)

    if not cred:
        raise HTTPException(status_code=400, detail=f"No hay credenciales activas para {ex_name.upper()}.")

    raw_key = decrypt_secret(cred["api_key_encrypted"])
    raw_secret = decrypt_secret(cred["api_secret_encrypted"])
    raw_pass = decrypt_secret(cred["api_passphrase_encrypted"]) if cred["api_passphrase_encrypted"] else ""

    if not hasattr(ccxt, ex_name):
        raise HTTPException(status_code=400, detail=f"Exchange {ex_name} no soportado por CCXT.")

    exchange_class = getattr(ccxt, ex_name)
    config = {
        "apiKey": raw_key,
        "secret": raw_secret,
        "enableRateLimit": True,
    }
    if raw_pass:
        config["password"] = raw_pass

    client = exchange_class(config)
    since_ms = int((datetime.now(timezone.utc) - timedelta(days=days)).timestamp() * 1000)

    try:
        raw_withdrawals = await client.fetch_withdrawals(code=currency.upper() if currency else None, since=since_ms, limit=200)
        inserted = []
        insert_query = """
            INSERT INTO account_withdrawals (exchange, currency, amount, fee, time, category, description, tx_id, is_matched)
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8, FALSE)
            ON CONFLICT (exchange, tx_id, time) DO NOTHING
            RETURNING id, exchange, currency, amount, fee, time, category, description, tx_id, is_matched;
        """
        async with pool.acquire() as conn:
            async with conn.transaction():
                for w in raw_withdrawals:
                    w_curr = (w.get('currency') or 'USDT').upper()
                    w_amount = float(w.get('amount') or 0.0)
                    w_fee = float((w.get('fee') or {}).get('cost') or 0.0)
                    w_time = datetime.fromtimestamp((w.get('timestamp') or 0) / 1000.0, tz=timezone.utc)
                    w_tx = str(w.get('txid') or w.get('id') or '')
                    row = await conn.fetchrow(
                        insert_query,
                        ex_name,
                        w_curr,
                        w_amount,
                        w_fee,
                        w_time,
                        "Retiro Exchange",
                        f"Retiro {w_amount} {w_curr} ({ex_name.upper()})",
                        w_tx
                    )
                    if row:
                        inserted.append(dict(row))

        return {
            "status": "ok",
            "exchange": ex_name,
            "total_fetched": len(raw_withdrawals),
            "new_withdrawals_count": len(inserted),
            "withdrawals": inserted
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error sincronizando retiros de {ex_name.upper()}: {e}")
    finally:
        await client.close()

@router.put("/{withdrawal_id}")
async def update_withdrawal(
    withdrawal_id: int = Path(...),
    payload: WithdrawalUpdate = Body(...)
):
    pool = await get_db_pool()
    updates = []
    params = []

    if payload.is_matched is not None:
        params.append(payload.is_matched)
        updates.append(f"is_matched = ${len(params)}")
    if payload.category is not None:
        params.append(payload.category)
        updates.append(f"category = ${len(params)}")
    if payload.description is not None:
        params.append(payload.description)
        updates.append(f"description = ${len(params)}")

    if not updates:
        raise HTTPException(status_code=400, detail="Sin campos para actualizar")

    params.append(withdrawal_id)
    query = f"UPDATE account_withdrawals SET {', '.join(updates)} WHERE id = ${len(params)} RETURNING *;"
    async with pool.acquire() as conn:
        row = await conn.fetchrow(query, *params)

    if not row:
        raise HTTPException(status_code=404, detail="Gasto/retiro no encontrado")

    return {"status": "ok", "withdrawal": dict(row)}

@router.delete("/{withdrawal_id}")
async def delete_withdrawal(withdrawal_id: int = Path(...)):
    pool = await get_db_pool()
    async with pool.acquire() as conn:
        res = await conn.execute("DELETE FROM account_withdrawals WHERE id = $1;", withdrawal_id)
        if res == "DELETE 0":
            raise HTTPException(status_code=404, detail="Gasto/retiro no encontrado")
    return {"status": "ok", "message": f"Retiro {withdrawal_id} eliminado."}
