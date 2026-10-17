from fastapi import APIRouter, Query, HTTPException, Body, Depends
from typing import Optional, List, Dict, Any
from datetime import datetime
from pydantic import BaseModel
from app.database import get_db_pool
from app.auth import verify_api_key

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

@router.get("", response_model=List[Dict[str, Any]])
async def get_trades(
    exchange: Optional[str] = None,
    symbol: Optional[str] = None,
    only_open: bool = Query(False, description="Solo compras no casadas / vivas"),
    limit: int = Query(100, ge=1, le=500),
):
    pool = await get_db_pool()
    query = "SELECT * FROM account_trades WHERE 1=1"
    params = []

    if exchange:
        params.append(exchange.lower())
        query += f" AND exchange = ${len(params)}"

    if symbol:
        params.append(symbol.replace('-', '/').upper())
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
            trade.exchange.lower(),
            trade.symbol.replace('-', '/').upper(),
            trade.side.lower(),
            trade.price,
            trade.amount,
            trade.fee,
            trade.fee_currency,
            trade.time,
            trade.amount,
            trade.notes,
        )
    return {"status": "ok", "id": trade_id}
