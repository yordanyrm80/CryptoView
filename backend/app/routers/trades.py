from fastapi import APIRouter, Query, HTTPException, Body, Depends, Path
from typing import Optional, List, Dict, Any
from datetime import datetime, timezone, timedelta
from pydantic import BaseModel, Field
import ccxt.async_support as ccxt

from app.database import get_db_pool
from app.auth import verify_api_key
from app.services.crypto import decrypt_secret

router = APIRouter(
    prefix="/api/v1/trades",
    tags=["Trades"],
    dependencies=[Depends(verify_api_key)]
)

class TradeCreate(BaseModel):
    trade_id: str
    order_id: Optional[str] = None
    exchange: str
    symbol: str
    side: str
    price: float
    amount: float
    fee: float = 0.0
    fee_currency: str = "USDT"
    time: datetime
    notes: Optional[str] = ""

class TradeUpdate(BaseModel):
    is_matched: Optional[bool] = None
    remaining_amount: Optional[float] = None
    notes: Optional[str] = None

@router.get("", response_model=List[Dict[str, Any]])
async def get_trades(
    exchange: Optional[str] = None,
    symbol: Optional[str] = None,
    only_open: bool = Query(False, description="Solo compras no casadas / vivas"),
    limit: int = Query(100, ge=1, le=1000),
):
    pool = await get_db_pool()
    query = "SELECT * FROM account_trades WHERE 1=1"
    params = []

    if exchange:
        params.append(exchange.lower().strip())
        query += f" AND exchange = ${len(params)}"

    if symbol:
        params.append(symbol.replace('-', '/').upper().strip())
        query += f" AND symbol = ${len(params)}"

    if only_open:
        query += " AND side = 'buy' AND is_matched = FALSE"

    params.append(limit)
    query += f" ORDER BY time DESC LIMIT ${len(params)}"

    async with pool.acquire() as conn:
        rows = await conn.fetch(query, *params)

    return [dict(r) for r in rows]

@router.post("", status_code=201)
async def create_trade(trade: TradeCreate):
    pool = await get_db_pool()
    query = """
        INSERT INTO account_trades (trade_id, order_id, exchange, symbol, side, price, amount, fee, fee_currency, time, remaining_amount, notes)
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12)
        ON CONFLICT (exchange, trade_id) DO NOTHING
        RETURNING id;
    """
    async with pool.acquire() as conn:
        trade_id = await conn.fetchval(
            query,
            trade.trade_id,
            trade.order_id,
            trade.exchange.lower().strip(),
            trade.symbol.replace('-', '/').upper().strip(),
            trade.side.lower().strip(),
            trade.price,
            trade.amount,
            trade.fee,
            trade.fee_currency,
            trade.time,
            trade.amount if trade.side.lower() == 'buy' else 0.0,
            trade.notes or "",
        )
    return {"status": "ok", "id": trade_id}

@router.post("/batch", status_code=201)
async def create_trades_batch(trades: List[TradeCreate]):
    """
    Inserta múltiples operaciones en una sola transacción atómica de alta velocidad.
    """
    if not trades:
        return {"status": "ok", "inserted": 0, "duplicates_skipped": 0}

    pool = await get_db_pool()
    query = """
        INSERT INTO account_trades (trade_id, order_id, exchange, symbol, side, price, amount, fee, fee_currency, time, remaining_amount, notes)
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12)
        ON CONFLICT (exchange, trade_id) DO NOTHING
        RETURNING id;
    """
    inserted = 0
    async with pool.acquire() as conn:
        async with conn.transaction():
            for t in trades:
                row_id = await conn.fetchval(
                    query,
                    t.trade_id,
                    t.order_id,
                    t.exchange.lower().strip(),
                    t.symbol.replace('-', '/').upper().strip(),
                    t.side.lower().strip(),
                    t.price,
                    t.amount,
                    t.fee,
                    t.fee_currency,
                    t.time,
                    t.amount if t.side.lower() == 'buy' else 0.0,
                    t.notes or "",
                )
                if row_id is not None:
                    inserted += 1

    return {
        "status": "ok",
        "total_received": len(trades),
        "inserted": inserted,
        "duplicates_skipped": len(trades) - inserted
    }

@router.post("/sync")
async def sync_trades_from_exchange(
    exchange: str = Query(..., description="Nombre del exchange (kucoin, binance, bingx)"),
    symbol: Optional[str] = Query(None, description="Par a sincronizar (ej. BTC/USDT). Si es null, sincroniza favoritas activas"),
    days: int = Query(1, ge=1, le=730, description="Días hacia atrás a consultar (1 = Hoy / últimas 24h)")
):
    """
    Conecta directamente con el exchange utilizando las credenciales cifradas en PostgreSQL,
    descarga las órdenes recién ejecutadas, las persiste en la base de datos y las retorna a la app.
    """
    ex_name = exchange.lower().strip()
    pool = await get_db_pool()

    # 1. Obtener credenciales cifradas
    async with pool.acquire() as conn:
        cred = await conn.fetchrow("""
            SELECT api_key_encrypted, api_secret_encrypted, api_passphrase_encrypted
            FROM api_keys
            WHERE exchange = $1 AND is_active = TRUE;
        """, ex_name)

    if not cred:
        raise HTTPException(status_code=400, detail=f"No hay credenciales activas configuradas para {ex_name.upper()}.")

    raw_key = decrypt_secret(cred["api_key_encrypted"])
    raw_secret = decrypt_secret(cred["api_secret_encrypted"])
    raw_pass = decrypt_secret(cred["api_passphrase_encrypted"]) if cred["api_passphrase_encrypted"] else ""

    if not hasattr(ccxt, ex_name):
        raise HTTPException(status_code=400, detail=f"Exchange {ex_name} no soportado.")

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

    # 2. Determinar qué símbolos consultar
    symbols_to_fetch: List[str] = []
    if symbol:
        symbols_to_fetch.append(symbol.replace('-', '/').upper().strip())
    else:
        async with pool.acquire() as conn:
            rows = await conn.fetch("SELECT symbol FROM tracked_symbols WHERE exchange = $1 AND is_active = TRUE;", ex_name)
            symbols_to_fetch = [r["symbol"] for r in rows]

    all_fetched_trades = []
    inserted_trades = []

    try:
        # Algunos exchanges (KuCoin) permiten fetch_my_trades sin símbolo específico
        if not symbol and ex_name == 'kucoin':
            try:
                trades = await client.fetch_my_trades(symbol=None, since=since_ms, limit=500)
                all_fetched_trades.extend(trades)
            except Exception:
                # Si falla sin símbolo, iterar por símbolos rastreados
                for sym in symbols_to_fetch:
                    try:
                        trades = await client.fetch_my_trades(symbol=sym, since=since_ms, limit=100)
                        all_fetched_trades.extend(trades)
                    except Exception:
                        pass
        else:
            for sym in symbols_to_fetch:
                try:
                    trades = await client.fetch_my_trades(symbol=sym, since=since_ms, limit=200)
                    all_fetched_trades.extend(trades)
                except Exception as e:
                    print(f"[SyncTrades Warn] {ex_name} {sym}: {e}")

        # 3. Guardar en PostgreSQL
        insert_query = """
            INSERT INTO account_trades (
                trade_id, order_id, exchange, symbol, side, price, amount, fee, fee_currency, time, remaining_amount, notes
            )
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12)
            ON CONFLICT (exchange, trade_id) DO NOTHING
            RETURNING id, trade_id, order_id, exchange, symbol, side, price, amount, fee, fee_currency, time, is_matched, remaining_amount, notes;
        """

        async with pool.acquire() as conn:
            async with conn.transaction():
                for t in all_fetched_trades:
                    t_id = str(t.get('id') or '')
                    if not t_id:
                        continue
                    t_sym = t.get('symbol', '').replace('-', '/').upper()
                    t_side = t.get('side', 'buy').lower()
                    t_price = float(t.get('price') or 0.0)
                    t_amount = float(t.get('amount') or 0.0)
                    t_fee = float((t.get('fee') or {}).get('cost') or 0.0)
                    t_fee_curr = (t.get('fee') or {}).get('currency') or 'USDT'
                    t_time = datetime.fromtimestamp((t.get('timestamp') or 0) / 1000.0, tz=timezone.utc)
                    order_id = str(t.get('order') or '')

                    row = await conn.fetchrow(
                        insert_query,
                        t_id,
                        order_id,
                        ex_name,
                        t_sym,
                        t_side,
                        t_price,
                        t_amount,
                        t_fee,
                        t_fee_curr,
                        t_time,
                        t_amount if t_side == 'buy' else 0.0,
                        f"Sincronizado vía Cloud API ({ex_name.upper()})"
                    )
                    if row:
                        inserted_trades.append(dict(row))

        return {
            "status": "ok",
            "exchange": ex_name,
            "days_checked": days,
            "total_fetched": len(all_fetched_trades),
            "new_trades_count": len(inserted_trades),
            "new_trades": inserted_trades
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error sincronizando con {ex_name.upper()}: {str(e)}")
    finally:
        await client.close()

@router.put("/{trade_id}")
async def update_trade(
    trade_id: int = Path(..., description="ID numérico interno del trade"),
    payload: TradeUpdate = Body(...)
):
    pool = await get_db_pool()
    updates = []
    params = []

    if payload.is_matched is not None:
        params.append(payload.is_matched)
        updates.append(f"is_matched = ${len(params)}")

    if payload.remaining_amount is not None:
        params.append(payload.remaining_amount)
        updates.append(f"remaining_amount = ${len(params)}")

    if payload.notes is not None:
        params.append(payload.notes)
        updates.append(f"notes = ${len(params)}")

    if not updates:
        raise HTTPException(status_code=400, detail="Sin campos para actualizar")

    params.append(trade_id)
    query = f"""
        UPDATE account_trades
        SET {', '.join(updates)}
        WHERE id = ${len(params)}
        RETURNING *;
    """
    async with pool.acquire() as conn:
        row = await conn.fetchrow(query, *params)

    if not row:
        raise HTTPException(status_code=404, detail="Trade no encontrado")

    return {"status": "ok", "trade": dict(row)}

@router.delete("/{trade_id}")
async def delete_trade(trade_id: int = Path(...)):
    pool = await get_db_pool()
    async with pool.acquire() as conn:
        res = await conn.execute("DELETE FROM account_trades WHERE id = $1;", trade_id)
        if res == "DELETE 0":
            raise HTTPException(status_code=404, detail="Trade no encontrado")
    return {"status": "ok", "message": f"Trade {trade_id} eliminado."}
