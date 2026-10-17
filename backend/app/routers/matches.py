from fastapi import APIRouter, Query, HTTPException, Body, Depends, Path
from typing import Optional, List, Dict, Any
from datetime import datetime
from pydantic import BaseModel, Field

from app.database import get_db_pool
from app.auth import verify_api_key

router = APIRouter(
    prefix="/api/v1/matches",
    tags=["Trade Matches (Diario & Casamientos)"],
    dependencies=[Depends(verify_api_key)]
)

class MatchCreate(BaseModel):
    buy_trade_id: int
    sell_trade_id: Optional[int] = None
    withdrawal_id: Optional[int] = None
    match_type: str = Field("trade", description="'trade' para casamiento con venta, 'expense' para consumo/retiro")
    matched_amount: float
    profit: float = 0.0
    time: datetime
    notes: Optional[str] = ""

@router.get("", response_model=List[Dict[str, Any]])
async def get_matches(
    match_type: Optional[str] = None,
    limit: int = Query(100, ge=1, le=1000)
):
    pool = await get_db_pool()
    query = """
        SELECT 
            m.id,
            m.buy_trade_id,
            m.sell_trade_id,
            m.withdrawal_id,
            m.match_type,
            m.matched_amount,
            m.profit,
            m.time,
            m.notes,
            bt.symbol,
            bt.exchange,
            bt.price AS buy_price,
            st.price AS sell_price
        FROM trade_matches m
        LEFT JOIN account_trades bt ON m.buy_trade_id = bt.id
        LEFT JOIN account_trades st ON m.sell_trade_id = st.id
        WHERE 1=1
    """
    params = []
    if match_type:
        params.append(match_type.lower().strip())
        query += f" AND m.match_type = ${len(params)}"

    params.append(limit)
    query += f" ORDER BY m.time DESC LIMIT ${len(params)}"

    async with pool.acquire() as conn:
        rows = await conn.fetch(query, *params)

    return [dict(r) for r in rows]

@router.get("/summary", response_model=Dict[str, Any])
async def get_matches_summary():
    """
    Devuelve métricas consolidadas del diario de casamientos: PnL total neto, total de casamientos y volumen.
    """
    pool = await get_db_pool()
    async with pool.acquire() as conn:
        row = await conn.fetchrow("""
            SELECT 
                COUNT(*) AS total_matches,
                COALESCE(SUM(profit), 0.0) AS total_net_profit,
                COALESCE(SUM(CASE WHEN profit > 0 THEN profit ELSE 0 END), 0.0) AS total_winning_profit,
                COALESCE(SUM(CASE WHEN profit < 0 THEN profit ELSE 0 END), 0.0) AS total_losing_profit,
                COUNT(CASE WHEN profit > 0 THEN 1 END) AS win_count,
                COUNT(CASE WHEN profit < 0 THEN 1 END) AS loss_count
            FROM trade_matches;
        """)
    return dict(row) if row else {}

@router.post("", status_code=201)
async def create_match(payload: MatchCreate):
    pool = await get_db_pool()
    insert_query = """
        INSERT INTO trade_matches (buy_trade_id, sell_trade_id, withdrawal_id, match_type, matched_amount, profit, time, notes)
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
        RETURNING id;
    """
    async with pool.acquire() as conn:
        async with conn.transaction():
            # 1. Verificar buy trade
            buy_trade = await conn.fetchrow("SELECT id, remaining_amount, amount FROM account_trades WHERE id = $1;", payload.buy_trade_id)
            if not buy_trade:
                raise HTTPException(status_code=404, detail="Operación de compra no encontrada")

            curr_rem = float(buy_trade["remaining_amount"])
            if payload.matched_amount > curr_rem + 0.000001:
                raise HTTPException(status_code=400, detail=f"Cantidad casada ({payload.matched_amount}) excede el remanente disponible ({curr_rem}).")

            # 2. Insertar match
            match_id = await conn.fetchval(
                insert_query,
                payload.buy_trade_id,
                payload.sell_trade_id,
                payload.withdrawal_id,
                payload.match_type.lower().strip(),
                payload.matched_amount,
                payload.profit,
                payload.time,
                payload.notes or "",
            )

            # 3. Descontar remaining_amount en compra y marcar is_matched si se consumió
            new_remaining = max(0.0, curr_rem - payload.matched_amount)
            is_full = new_remaining < 0.00001
            await conn.execute("""
                UPDATE account_trades
                SET remaining_amount = $1, is_matched = $2
                WHERE id = $3;
            """, new_remaining, is_full, payload.buy_trade_id)

            # 4. Si fue venta, marcar venta como casada
            if payload.sell_trade_id:
                await conn.execute("UPDATE account_trades SET is_matched = TRUE WHERE id = $1;", payload.sell_trade_id)

            # 5. Si fue gasto, marcar retiro como casado
            if payload.withdrawal_id:
                await conn.execute("UPDATE account_withdrawals SET is_matched = TRUE WHERE id = $1;", payload.withdrawal_id)

    return {"status": "ok", "match_id": match_id}

@router.delete("/{match_id}")
async def delete_match(match_id: int = Path(...)):
    """
    Elimina un casamiento y repone automáticamente el saldo remanente a la compra original.
    """
    pool = await get_db_pool()
    async with pool.acquire() as conn:
        async with conn.transaction():
            match = await conn.fetchrow("SELECT buy_trade_id, matched_amount, sell_trade_id, withdrawal_id FROM trade_matches WHERE id = $1;", match_id)
            if not match:
                raise HTTPException(status_code=404, detail="Casamiento no encontrado")

            # Reponer remaining_amount
            await conn.execute("""
                UPDATE account_trades
                SET remaining_amount = remaining_amount + $1, is_matched = FALSE
                WHERE id = $2;
            """, float(match["matched_amount"]), match["buy_trade_id"])

            if match["sell_trade_id"]:
                await conn.execute("UPDATE account_trades SET is_matched = FALSE WHERE id = $1;", match["sell_trade_id"])

            if match["withdrawal_id"]:
                await conn.execute("UPDATE account_withdrawals SET is_matched = FALSE WHERE id = $1;", match["withdrawal_id"])

            await conn.execute("DELETE FROM trade_matches WHERE id = $1;", match_id)

    return {"status": "ok", "message": f"Casamiento {match_id} deshecho exitosamente."}
