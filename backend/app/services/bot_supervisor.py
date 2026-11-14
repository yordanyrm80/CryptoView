import asyncio
import json
import time
import uuid
from datetime import datetime, timezone
from typing import Any, Awaitable, Callable, Dict, List, Optional, Tuple

import pandas as pd

try:
    import httpx
except ImportError:  # pragma: no cover - optional in local minimal test envs
    httpx = None  # type: ignore

try:
    import ccxt.async_support as ccxt
except ImportError:  # pragma: no cover - optional in local minimal test envs
    ccxt = None  # type: ignore

from app.config import settings
from app.database import close_db_pool, init_db_pool

try:
    from app.services.crypto import decrypt_secret
except ImportError:  # pragma: no cover - fallback when cryptography is absent locally
    def decrypt_secret(value: Optional[str]) -> Optional[str]:
        return value

from app.strategies import (
    ActionSignal,
    BotConfigModel,
    BtcQuantumEvolutionRegimeStrategy,
    MarketRegimeDetector,
    PortfolioState,
    SignalType,
    TechnicalIndicators,
    TrancheModel,
    TrancheStatus,
)

DEFAULT_DISCORD_WEBHOOK_URL = (
    settings.DISCORD_WEBHOOK_URL.strip() if settings.DISCORD_WEBHOOK_URL else ""
)

DEFAULT_FEE_RATE = 0.001
STOP_SLIPPAGE = 0.0005
RECYCLE_PROFIT_FRACTION = 0.35
MAX_SUBSIDIZED_DISCOUNT_PCT = 0.12
MIN_ORDER_NOTIONAL_USDT = 10.0
BALANCE_SYNC_THRESHOLD_USDT = 1.0
ONE_HOUR_MS = 3_600_000

ExchangeFactory = Callable[[Any, Dict[str, Any]], Awaitable[Any]]


def _split_symbol(symbol: str) -> Tuple[str, str]:
    """Splits a spot pair like 'BTC/USDT' into (base_coin, quote_coin)."""
    if "/" in symbol:
        base, quote = symbol.split("/", 1)
        return base.strip().upper(), quote.strip().upper()
    return symbol.strip().upper(), "USDT"


async def send_discord_bot_embed(
    conn,
    event_kind: str,
    title: str,
    description: str = "",
    color: int = 0x3498DB,
    fields: Optional[List[Dict[str, Any]]] = None,
    footer_text: str = "Apex Quant Engine • KuCoin Spot",
) -> bool:
    """Sends a Discord Rich Embed notification using system_settings or default webhook URL."""
    if httpx is None:
        return False
    try:
        url = DEFAULT_DISCORD_WEBHOOK_URL
        notify_buys = True
        notify_sells = True
        notify_plateau = True

        row = await conn.fetchrow(
            "SELECT value_json FROM system_settings WHERE key = 'bot_notifications';"
        )
        if row and row["value_json"]:
            cfg = (
                json.loads(row["value_json"])
                if isinstance(row["value_json"], str)
                else row["value_json"]
            )
            custom_url = (cfg.get("discord_webhook_url") or "").strip()
            if custom_url.startswith("http"):
                url = custom_url
            notify_buys = bool(cfg.get("notify_buys", True))
            notify_sells = bool(cfg.get("notify_sells", True))
            notify_plateau = bool(cfg.get("notify_plateau", True))

        if not url.startswith("http"):
            return False
        if event_kind == "BUY" and not notify_buys:
            return False
        if event_kind == "SELL" and not notify_sells:
            return False
        if event_kind == "PLATEAU" and not notify_plateau:
            return False

        payload = {
            "username": "Apex Quant",
            "embeds": [
                {
                    "title": title,
                    "description": description,
                    "color": color,
                    "fields": fields or [],
                    "footer": {"text": footer_text},
                    "timestamp": datetime.now(timezone.utc).isoformat(),
                }
            ],
        }
        async with httpx.AsyncClient(timeout=8.0) as client:
            resp = await client.post(url, json=payload)
            return resp.status_code in (200, 204)
    except Exception as e:
        print(f"[Discord Notification Warn] {e}")
        return False


async def _get_active_exchange_proxy(conn) -> Optional[str]:
    """Retrieves and decrypts the active outbound proxy for exchange communication."""
    try:
        row = await conn.fetchrow(
            "SELECT value_json FROM system_settings WHERE key = 'exchange_proxy';"
        )
        if not row or not row["value_json"]:
            return getattr(settings, "KUCOIN_PROXY_URL", None) or None
        raw = row["value_json"]
        data = json.loads(raw) if isinstance(raw, str) else raw
        if not data.get("enabled", True):
            return None
        proxy_raw = data.get("proxy_url")
        if not proxy_raw:
            return None
        decrypted = decrypt_secret(proxy_raw) or proxy_raw
        return decrypted.strip() if decrypted else None
    except Exception as e:
        print(f"[BotSupervisor Proxy Warning] Error reading proxy from DB: {e}")
        return getattr(settings, "KUCOIN_PROXY_URL", None) or None


async def _create_subaccount_exchange(conn, cfg: Dict[str, Any]):
    """Creates, configures, and loads markets for an isolated KuCoin subaccount client."""
    if ccxt is None:
        raise RuntimeError("ccxt library is not available in this environment.")

    raw_key = (cfg.get("api_key") or "").strip()
    raw_secret = (cfg.get("api_secret") or "").strip()
    raw_pass = (cfg.get("api_passphrase") or "").strip()

    api_key = decrypt_secret(raw_key) or raw_key
    api_secret = decrypt_secret(raw_secret) or raw_secret
    api_pass = decrypt_secret(raw_pass) or raw_pass

    if not (api_key and api_secret and api_pass):
        raise ValueError("Missing dedicated subaccount credentials for LIVE execution.")

    exchange_params: Dict[str, Any] = {
        "apiKey": api_key,
        "secret": api_secret,
        "password": api_pass,
        "enableRateLimit": True,
    }
    proxy_url = await _get_active_exchange_proxy(conn)
    if proxy_url:
        exchange_params["aiohttp_proxy"] = proxy_url

    ex = ccxt.kucoin(exchange_params)
    try:
        await ex.load_markets()
        return ex
    except Exception:
        await ex.close()
        raise


def _format_precision_amount(ex, symbol: str, amount: float) -> float:
    """Formats order amount according to exchange market precision."""
    if hasattr(ex, "amount_to_precision"):
        return float(ex.amount_to_precision(symbol, amount))
    return float(f"{amount:.8f}")


def _format_precision_price(ex, symbol: str, price: float) -> float:
    """Formats order price according to exchange market precision."""
    if hasattr(ex, "price_to_precision"):
        return float(ex.price_to_precision(symbol, price))
    return float(f"{price:.2f}")


def _extract_fill_metrics(
    order_data: Optional[Dict[str, Any]],
    symbol: str,
    default_fee_rate: float = DEFAULT_FEE_RATE,
) -> Dict[str, Any]:
    """Extracts normalized status, average fill price, filled amount, cost, and quote fee."""
    data = order_data or {}
    base_coin, quote_coin = _split_symbol(symbol)

    raw_status = (data.get("status") or "open").strip().lower()
    if raw_status == "cancelled":
        raw_status = "canceled"
    elif raw_status == "filled":
        raw_status = "closed"

    filled = float(data.get("filled") or 0.0)
    remaining = float(data.get("remaining") or 0.0)
    cost = float(data.get("cost") or 0.0)
    limit_price = float(data.get("price") or 0.0)

    if data.get("average") is not None and float(data["average"]) > 0:
        avg_price = float(data["average"])
    elif filled > 0 and cost > 0:
        avg_price = cost / filled
    else:
        avg_price = limit_price

    if cost <= 0 and filled > 0 and avg_price > 0:
        cost = filled * avg_price

    fee_usdt = 0.0
    saw_numeric_fee = False
    fees_list = data.get("fees") if isinstance(data.get("fees"), list) and data.get("fees") else None
    fee_entries = fees_list or ([data["fee"]] if isinstance(data.get("fee"), dict) else [])

    for entry in fee_entries:
        if not isinstance(entry, dict) or entry.get("cost") is None:
            continue
        f_cost = float(entry["cost"])
        saw_numeric_fee = True
        if f_cost <= 0:
            continue
        f_curr = (entry.get("currency") or quote_coin).strip().upper()
        if f_curr == quote_coin:
            fee_usdt += f_cost
        elif f_curr == base_coin and avg_price > 0:
            fee_usdt += f_cost * avg_price

    if not saw_numeric_fee and filled > 0 and cost > 0:
        fee_usdt = cost * default_fee_rate

    ts = data.get("lastTradeTimestamp") or data.get("timestamp")
    ts_ms = int(ts) if ts else int(time.time() * 1000)

    return {
        "status": raw_status,
        "filled": filled,
        "remaining": remaining,
        "avg_price": avg_price,
        "cost": cost,
        "fee_usdt": fee_usdt,
        "timestamp": ts_ms,
        "limit_price": limit_price,
    }


async def _fetch_order_safe(ex, order_id: str, symbol: str) -> Optional[Dict[str, Any]]:
    """Fetches a single order state from the exchange without crashing the supervisor loop."""
    try:
        return await ex.fetch_order(order_id, symbol)
    except Exception as e:
        print(f"[BotSupervisor Order Fetch Warn] {order_id} ({symbol}): {e}")
        return None


async def _cancel_order_safe(ex, order_id: str, symbol: str) -> Optional[Dict[str, Any]]:
    """Cancels an exchange order and returns its final reconciled order state."""
    try:
        await ex.cancel_order(order_id, symbol)
    except Exception as e:
        err_name = type(e).__name__.lower()
        err_msg = str(e).lower()
        if "notfound" not in err_name and "not exist" not in err_msg and "already" not in err_msg:
            print(f"[BotSupervisor Cancel Warn] {order_id} ({symbol}): {e}")
    return await _fetch_order_safe(ex, order_id, symbol)


async def _place_limit_order(
    ex,
    symbol: str,
    side: str,
    amount: float,
    price: float,
) -> Dict[str, Any]:
    """Places a Maker/Limit order formatted to exact exchange precision."""
    fmt_amount = _format_precision_amount(ex, symbol, amount)
    fmt_price = _format_precision_price(ex, symbol, price)
    if fmt_amount <= 0 or fmt_price <= 0:
        raise ValueError(f"Invalid precision-formatted limit order params: amt={fmt_amount}, px={fmt_price}")
    return await ex.create_order(
        symbol=symbol,
        type="limit",
        side=side,
        amount=fmt_amount,
        price=fmt_price,
    )


async def _place_market_sell_order(ex, symbol: str, amount: float) -> Dict[str, Any]:
    """Places an emergency market sell order (used exclusively for Trailing Stop exits)."""
    fmt_amount = _format_precision_amount(ex, symbol, amount)
    if fmt_amount <= 0:
        raise ValueError(f"Invalid precision-formatted market sell amount: {fmt_amount}")
    return await ex.create_order(
        symbol=symbol,
        type="market",
        side="sell",
        amount=fmt_amount,
    )


async def _ensure_runtime_schema(conn) -> None:
    """Ensures idempotent runtime linkage columns exist for live limit order tracking."""
    statements = (
        "ALTER TABLE tranches ADD COLUMN IF NOT EXISTS highest_price DOUBLE PRECISION DEFAULT 0.0;",
        "ALTER TABLE tranches ADD COLUMN IF NOT EXISTS sell_order_id VARCHAR(64);",
        "ALTER TABLE orders ADD COLUMN IF NOT EXISTS tranche_index INTEGER;",
        "ALTER TABLE orders ADD COLUMN IF NOT EXISTS tranche_id INTEGER;",
        "ALTER TABLE orders ADD COLUMN IF NOT EXISTS candle_timestamp BIGINT;",
        "ALTER TABLE orders ADD COLUMN IF NOT EXISTS target_sell_price DOUBLE PRECISION;",
        "ALTER TABLE orders ADD COLUMN IF NOT EXISTS reason TEXT;",
    )
    for stmt in statements:
        await conn.execute(stmt)


async def _load_hourly_candles_df(conn, symbol: str) -> pd.DataFrame:
    """Loads up to 5,000 completed hourly candles from TimescaleDB (candles_1h).

    Strict parity with SimulationEngine: Only closed/completed 1-hour candles are returned.
    In-progress hourly buckets are excluded so indicators and buy entries evaluate strictly
    on candle close, preventing premature entries on intrabar noise wicks.
    """
    rows = await conn.fetch(
        """
        SELECT
            (EXTRACT(EPOCH FROM time)::BIGINT * 1000) AS timestamp,
            open,
            high,
            low,
            close,
            volume
        FROM candles_1h
        WHERE exchange = 'kucoin' AND symbol = $1
          AND time < date_trunc('hour', NOW())
        ORDER BY time DESC
        LIMIT 5000;
        """,
        symbol,
    )
    if not rows or len(rows) < 50:
        return pd.DataFrame()

    records = [dict(r) for r in reversed(rows)]
    return pd.DataFrame(records)


async def _get_post_buy_extremes(
    conn,
    symbol: str,
    since_ms: Optional[int],
    latest_candle_ts: int,
    latest_row_high: float,
    latest_row_low: float,
    fallback_price: float,
) -> Tuple[float, float]:
    """Returns intrabar (high, low) strictly after since_ms without leaking pre-buy candle wicks."""
    row = await conn.fetchrow(
        """
        SELECT MAX(high) AS max_high, MIN(low) AS min_low
        FROM market_candles
        WHERE exchange = 'kucoin'
          AND symbol = $1
          AND time > TO_TIMESTAMP($2 / 1000.0);
        """,
        symbol,
        int(since_ms or latest_candle_ts),
    )
    mc_high = float(row["max_high"]) if row and row["max_high"] is not None else None
    mc_low = float(row["min_low"]) if row and row["min_low"] is not None else None

    # Only include the latest closed 1h candle extremes if it started at or after since_ms
    if since_ms is not None and latest_candle_ts >= since_ms:
        high_candidates = [v for v in (latest_row_high, mc_high) if v is not None and v > 0]
        low_candidates = [v for v in (latest_row_low, mc_low) if v is not None and v > 0]
    else:
        high_candidates = [v for v in (mc_high,) if v is not None and v > 0]
        low_candidates = [v for v in (mc_low,) if v is not None and v > 0]

    eff_high = max(high_candidates) if high_candidates else fallback_price
    eff_low = min(low_candidates) if low_candidates else fallback_price
    return eff_high, eff_low


async def _record_order_row(
    conn,
    order_id: str,
    bot_id: str,
    symbol: str,
    side: str,
    order_type: str,
    price: float,
    amount: float,
    status: str,
    fee: float,
    created_at: int,
    filled_at: Optional[int] = None,
    tranche_index: Optional[int] = None,
    tranche_id: Optional[int] = None,
    candle_timestamp: Optional[int] = None,
    target_sell_price: Optional[float] = None,
    reason: Optional[str] = None,
) -> None:
    """Inserts or updates an order record cleanly across both simulated and live flows."""
    await conn.execute(
        """
        INSERT INTO orders (
            id, bot_id, symbol, side, order_type, price, amount, status, fee,
            created_at, filled_at, tranche_index, tranche_id, candle_timestamp,
            target_sell_price, reason
        )
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16)
        ON CONFLICT (id) DO UPDATE SET
            price = EXCLUDED.price,
            amount = EXCLUDED.amount,
            status = EXCLUDED.status,
            fee = EXCLUDED.fee,
            filled_at = COALESCE(EXCLUDED.filled_at, orders.filled_at),
            tranche_index = COALESCE(EXCLUDED.tranche_index, orders.tranche_index),
            tranche_id = COALESCE(EXCLUDED.tranche_id, orders.tranche_id),
            candle_timestamp = COALESCE(EXCLUDED.candle_timestamp, orders.candle_timestamp),
            target_sell_price = COALESCE(EXCLUDED.target_sell_price, orders.target_sell_price),
            reason = COALESCE(EXCLUDED.reason, orders.reason);
        """,
        order_id,
        bot_id,
        symbol,
        side,
        order_type,
        float(price),
        float(amount),
        status,
        float(fee),
        int(created_at),
        filled_at,
        tranche_index,
        tranche_id,
        candle_timestamp,
        target_sell_price,
        reason,
    )


async def _activate_tranche(
    conn,
    bot_id: str,
    symbol: str,
    tranche_index: int,
    cost: float,
    exec_price: float,
    amount: float,
    target_sell: float,
    buy_fee: float,
    buy_ts: int,
    reason: str,
    dry_run: bool,
    portfolio: PortfolioState,
) -> TrancheModel:
    """Persists a newly filled ACTIVE tranche, updates portfolio cash, logs event & Discord."""
    new_id = await conn.fetchval(
        """
        INSERT INTO tranches (
            bot_id, symbol, tranche_index, allocated_budget, buy_price, amount,
            target_sell_price, highest_price, status, buy_fee, buy_timestamp,
            profit_usdt, subsidized_satoshis
        )
        VALUES ($1, $2, $3, $4, $5, $6, $7, $5, 'ACTIVE', $8, $9, 0.0, 0.0)
        RETURNING id;
        """,
        bot_id,
        symbol,
        int(tranche_index),
        float(cost),
        float(exec_price),
        float(amount),
        float(target_sell),
        float(buy_fee),
        int(buy_ts),
    )

    await conn.execute(
        """
        INSERT INTO bot_events (bot_id, event_type, details, timestamp)
        VALUES ($1, 'BUY', $2, $3);
        """,
        bot_id,
        f"Compra ejecutada T{tranche_index} @ ${exec_price:.2f} ({cost:.2f} USDT) -> Objetivo TP: ${target_sell:.2f} ({reason})",
        int(buy_ts),
    )

    portfolio.available_usdt = max(0.0, portfolio.available_usdt - (cost + buy_fee))
    tranche = TrancheModel(
        id=new_id,
        bot_id=bot_id,
        symbol=symbol,
        tranche_index=int(tranche_index),
        allocated_budget=float(cost),
        buy_price=float(exec_price),
        amount=float(amount),
        target_sell_price=float(target_sell),
        status=TrancheStatus.ACTIVE,
        buy_fee=float(buy_fee),
        buy_timestamp=int(buy_ts),
    )
    portfolio.active_tranches.append(tranche)

    mode_prefix = "🟡 [SIM] " if dry_run else "🟢 "
    coin = _split_symbol(symbol)[0]
    tp_pct = ((target_sell / exec_price) - 1.0) * 100.0 if exec_price > 0 else 0.0
    await send_discord_bot_embed(
        conn,
        event_kind="BUY",
        title=f"{mode_prefix}BUY T{tranche_index} • {symbol} @ ${exec_price:,.2f}",
        color=0x2ECC71 if dry_run else 0x00E676,
        fields=[
            {"name": "Volumen", "value": f"`{amount:.6f} {coin}` (${cost:,.2f})", "inline": True},
            {"name": "Objetivo TP", "value": f"`${target_sell:,.2f}` (+{tp_pct:.2f}%)", "inline": True},
            {"name": "Señal / Régimen", "value": f"`{reason}`", "inline": False},
        ],
        footer_text=f"{bot_id} • {'Simulación Paper' if dry_run else 'Maker Limit'}",
    )
    mode_tag = "SIMULACIÓN" if dry_run else "EN VIVO"
    print(
        f"[BotSupervisor] 🟢 {bot_id} ({mode_tag}) BUY T{tranche_index} @ ${exec_price:.2f} (${cost:.2f} USDT) -> TP ${target_sell:.2f}"
    )
    return tranche


async def _ensure_resting_sell_order(
    conn,
    ex,
    bot_id: str,
    symbol: str,
    tranche: TrancheModel,
    now_ms: int,
    sell_amount: float,
    dry_run: bool,
    portfolio: PortfolioState,
    open_sell_orders_by_tranche: Dict[int, Any],
    base_free_tracker: Optional[List[float]] = None,
) -> Optional[str]:
    """Ensures an ACTIVE tranche has an open resting SELL LIMIT order on KuCoin."""
    if tranche.id is None or tranche.target_sell_price <= 0:
        return None
    if tranche.id in open_sell_orders_by_tranche:
        return open_sell_orders_by_tranche[tranche.id]["id"]

    candidate_amt = float(sell_amount)
    if base_free_tracker is not None and candidate_amt > base_free_tracker[0]:
        candidate_amt = max(0.0, base_free_tracker[0])

    try:
        fmt_amt = _format_precision_amount(ex, symbol, candidate_amt)
        fmt_price = _format_precision_price(ex, symbol, tranche.target_sell_price)
        if fmt_amt <= 0 or fmt_amt * fmt_price < 1.0:
            return None

        placed = await _place_limit_order(ex, symbol, "sell", fmt_amt, fmt_price)
        ord_id = str(placed["id"])
        latest = await _fetch_order_safe(ex, ord_id, symbol) or placed
        metrics = _extract_fill_metrics(latest, symbol, DEFAULT_FEE_RATE)

        if metrics["status"] == "closed" and metrics["filled"] > 0:
            await _record_order_row(
                conn,
                order_id=ord_id,
                bot_id=bot_id,
                symbol=symbol,
                side="SELL",
                order_type="LIMIT",
                price=metrics["avg_price"],
                amount=metrics["filled"],
                status="CLOSED",
                fee=metrics["fee_usdt"],
                created_at=now_ms,
                filled_at=metrics["timestamp"] or now_ms,
                tranche_index=tranche.tranche_index,
                tranche_id=tranche.id,
                target_sell_price=tranche.target_sell_price,
                reason=f"Take Profit hit ({tranche.target_sell_price:.2f}) [T{tranche.tranche_index}]",
            )
            if base_free_tracker is not None:
                base_free_tracker[0] = max(0.0, base_free_tracker[0] - metrics["filled"])
            await _close_tranche_and_recycle(
                conn=conn,
                bot_id=bot_id,
                symbol=symbol,
                tranche=tranche,
                exec_price=metrics["avg_price"],
                filled_amount=metrics["filled"],
                sell_fee=metrics["fee_usdt"],
                sell_ts=metrics["timestamp"] or now_ms,
                reason=f"Take Profit Limit T{tranche.tranche_index}",
                dry_run=dry_run,
                portfolio=portfolio,
                ex=ex,
                open_sell_orders_by_tranche=open_sell_orders_by_tranche,
                base_free_tracker=base_free_tracker,
            )
            return None

        await _record_order_row(
            conn,
            order_id=ord_id,
            bot_id=bot_id,
            symbol=symbol,
            side="SELL",
            order_type="LIMIT",
            price=fmt_price,
            amount=fmt_amt,
            status="OPEN",
            fee=0.0,
            created_at=now_ms,
            filled_at=None,
            tranche_index=tranche.tranche_index,
            tranche_id=tranche.id,
            target_sell_price=tranche.target_sell_price,
            reason=f"Resting TP T{tranche.tranche_index}",
        )
        await conn.execute(
            "UPDATE tranches SET sell_order_id = $1 WHERE id = $2;",
            ord_id,
            tranche.id,
        )
        open_sell_orders_by_tranche[tranche.id] = {
            "id": ord_id,
            "tranche_id": tranche.id,
            "tranche_index": tranche.tranche_index,
            "price": fmt_price,
            "amount": fmt_amt,
        }
        if base_free_tracker is not None:
            base_free_tracker[0] = max(0.0, base_free_tracker[0] - fmt_amt)
        print(
            f"[BotSupervisor] 📌 {bot_id} SELL LIMIT resting T{tranche.tranche_index} "
            f"{fmt_amt} @ ${fmt_price:.2f} (id={ord_id})"
        )
        return ord_id
    except Exception as e:
        print(
            f"[BotSupervisor Resting Sell Warn] {bot_id} T{tranche.tranche_index} "
            f"@ ${tranche.target_sell_price:.2f}: {e}"
        )
        return None


async def _close_tranche_and_recycle(
    conn,
    bot_id: str,
    symbol: str,
    tranche: TrancheModel,
    exec_price: float,
    filled_amount: float,
    sell_fee: float,
    sell_ts: int,
    reason: str,
    dry_run: bool,
    portfolio: PortfolioState,
    ex: Any = None,
    open_sell_orders_by_tranche: Optional[Dict[int, Any]] = None,
    base_free_tracker: Optional[List[float]] = None,
) -> float:
    """Closes a sold tranche, applies 35% cascading profit recycling, and updates resting sells."""
    revenue_gross = filled_amount * exec_price
    revenue_net = revenue_gross - sell_fee
    cost_basis = tranche.allocated_budget + (tranche.buy_fee or 0.0)
    realized_profit = revenue_net - cost_basis

    tranche.status = TrancheStatus.CLOSED
    await conn.execute(
        """
        UPDATE tranches
        SET status = 'CLOSED',
            actual_sell_price = $1,
            sell_fee = $2,
            sell_timestamp = $3,
            profit_usdt = $4,
            sell_order_id = NULL
        WHERE id = $5;
        """,
        float(exec_price),
        float(sell_fee),
        int(sell_ts),
        float(realized_profit),
        tranche.id,
    )

    if open_sell_orders_by_tranche is not None and tranche.id in open_sell_orders_by_tranche:
        open_sell_orders_by_tranche.pop(tranche.id, None)

    await conn.execute(
        """
        INSERT INTO bot_events (bot_id, event_type, details, timestamp)
        VALUES ($1, 'SELL', $2, $3);
        """,
        bot_id,
        f"Venta ejecutada T{tranche.tranche_index} @ ${exec_price:.2f} ({reason}). Beneficio: {realized_profit:+.2f} USDT",
        int(sell_ts),
    )

    if tranche in portfolio.active_tranches:
        portfolio.active_tranches.remove(tranche)
    portfolio.available_usdt += revenue_net
    portfolio.total_realized_profit += realized_profit

    # Cascading Subsidized Profit Recycling (35% profit cut down to -12% floor)
    if realized_profit > 0 and portfolio.active_tranches:
        remaining_discount = realized_profit * RECYCLE_PROFIT_FRACTION
        hung_tranches = [
            t for t in portfolio.active_tranches if t.buy_price > tranche.buy_price
        ]
        hung_tranches.sort(key=lambda t: t.buy_price, reverse=True)
        for hung in hung_tranches:
            if remaining_discount <= 0.001:
                break
            floor_min = hung.buy_price * (1.0 - MAX_SUBSIDIZED_DISCOUNT_PCT)
            max_reduction = hung.target_sell_price - floor_min
            if max_reduction <= 0:
                continue
            max_absorbable_usdt = max_reduction * hung.amount
            apply_discount = min(remaining_discount, max_absorbable_usdt)
            old_target = hung.target_sell_price
            hung.target_sell_price -= apply_discount / hung.amount
            hung.subsidized_satoshis += apply_discount
            remaining_discount -= apply_discount

            await conn.execute(
                """
                UPDATE tranches
                SET target_sell_price = $1, subsidized_satoshis = $2
                WHERE id = $3;
                """,
                float(hung.target_sell_price),
                float(hung.subsidized_satoshis),
                hung.id,
            )

            # In LIVE mode, cancel and replace any resting SELL LIMIT at the lower target
            if (
                not dry_run
                and ex is not None
                and hung.id is not None
                and abs(hung.target_sell_price - old_target) > 0.01
                and open_sell_orders_by_tranche is not None
                and hung.id in open_sell_orders_by_tranche
            ):
                old_sell_row = open_sell_orders_by_tranche[hung.id]
                old_sell_id = old_sell_row["id"]
                final_old = await _cancel_order_safe(ex, old_sell_id, symbol)
                old_metrics = _extract_fill_metrics(final_old, symbol, DEFAULT_FEE_RATE)
                if old_metrics["status"] == "closed" and old_metrics["filled"] > 0:
                    await _record_order_row(
                        conn,
                        order_id=old_sell_id,
                        bot_id=bot_id,
                        symbol=symbol,
                        side="SELL",
                        order_type="LIMIT",
                        price=old_metrics["avg_price"],
                        amount=old_metrics["filled"],
                        status="CLOSED",
                        fee=old_metrics["fee_usdt"],
                        created_at=sell_ts,
                        filled_at=old_metrics["timestamp"] or sell_ts,
                        tranche_index=hung.tranche_index,
                        tranche_id=hung.id,
                    )
                    open_sell_orders_by_tranche.pop(hung.id, None)
                    await _close_tranche_and_recycle(
                        conn=conn,
                        bot_id=bot_id,
                        symbol=symbol,
                        tranche=hung,
                        exec_price=old_metrics["avg_price"],
                        filled_amount=old_metrics["filled"],
                        sell_fee=old_metrics["fee_usdt"],
                        sell_ts=old_metrics["timestamp"] or sell_ts,
                        reason=f"Take Profit Limit T{hung.tranche_index}",
                        dry_run=dry_run,
                        portfolio=portfolio,
                        ex=ex,
                        open_sell_orders_by_tranche=open_sell_orders_by_tranche,
                        base_free_tracker=base_free_tracker,
                    )
                else:
                    await conn.execute(
                        "UPDATE orders SET status = 'CANCELED' WHERE id = $1;",
                        old_sell_id,
                    )
                    await conn.execute(
                        "UPDATE tranches SET sell_order_id = NULL WHERE id = $1;",
                        hung.id,
                    )
                    open_sell_orders_by_tranche.pop(hung.id, None)
                    if base_free_tracker is not None:
                        base_free_tracker[0] += float(old_sell_row.get("amount") or hung.amount)
                    await _ensure_resting_sell_order(
                        conn=conn,
                        ex=ex,
                        bot_id=bot_id,
                        symbol=symbol,
                        tranche=hung,
                        now_ms=sell_ts,
                        sell_amount=hung.amount,
                        dry_run=dry_run,
                        portfolio=portfolio,
                        open_sell_orders_by_tranche=open_sell_orders_by_tranche,
                        base_free_tracker=base_free_tracker,
                    )

    mode_prefix = "🟡 [SIM] " if dry_run else "💰 "
    profit_sign = "+" if realized_profit >= 0 else ""
    await send_discord_bot_embed(
        conn,
        event_kind="SELL",
        title=f"{mode_prefix}TAKE PROFIT T{tranche.tranche_index} • {symbol} @ ${exec_price:,.2f}",
        color=0xFFD700 if realized_profit >= 0 else 0xE67E22,
        fields=[
            {"name": "Beneficio Neto", "value": f"**{profit_sign}${realized_profit:,.2f} USDT**", "inline": True},
            {"name": "Estado / Motivo", "value": f"`{reason}`", "inline": True},
        ],
        footer_text=f"{bot_id} • Cash Flow Realizado",
    )
    mode_tag = "SIMULACIÓN" if dry_run else "EN VIVO"
    print(
        f"[BotSupervisor] 💰 {bot_id} ({mode_tag}) SELL T{tranche.tranche_index} @ ${exec_price:.2f} | Profit: {realized_profit:+.2f} USDT"
    )
    return realized_profit


async def _finalize_filled_buy_order(
    conn,
    ex,
    bot_id: str,
    symbol: str,
    ord_id: str,
    ord_idx: int,
    metrics: Dict[str, Any],
    target_mult: float,
    reason: str,
    now_ms: int,
    portfolio: PortfolioState,
    open_sell_orders_by_tranche: Dict[int, Any],
    base_free_tracker: Optional[List[float]],
) -> TrancheModel:
    """Marks a filled BUY LIMIT order CLOSED, activates its tranche, and places its resting SELL LIMIT."""
    await conn.execute(
        """
        UPDATE orders
        SET status = 'CLOSED', price = $1, amount = $2, fee = $3, filled_at = $4
        WHERE id = $5;
        """,
        float(metrics["avg_price"]),
        float(metrics["filled"]),
        float(metrics["fee_usdt"]),
        int(metrics["timestamp"] or now_ms),
        ord_id,
    )
    new_tranche = await _activate_tranche(
        conn=conn,
        bot_id=bot_id,
        symbol=symbol,
        tranche_index=ord_idx,
        cost=metrics["cost"],
        exec_price=metrics["avg_price"],
        amount=metrics["filled"],
        target_sell=metrics["avg_price"] * target_mult,
        buy_fee=metrics["fee_usdt"],
        buy_ts=metrics["timestamp"] or now_ms,
        reason=reason,
        dry_run=False,
        portfolio=portfolio,
    )
    await conn.execute(
        "UPDATE orders SET tranche_id = $1 WHERE id = $2;",
        new_tranche.id,
        ord_id,
    )
    if base_free_tracker is not None:
        base_free_tracker[0] += metrics["filled"]
    await _ensure_resting_sell_order(
        conn=conn,
        ex=ex,
        bot_id=bot_id,
        symbol=symbol,
        tranche=new_tranche,
        now_ms=now_ms,
        sell_amount=new_tranche.amount,
        dry_run=False,
        portfolio=portfolio,
        open_sell_orders_by_tranche=open_sell_orders_by_tranche,
        base_free_tracker=base_free_tracker,
    )
    return new_tranche


async def _reconcile_live_open_orders(
    conn,
    ex,
    bot_id: str,
    symbol: str,
    latest_candle_ts: int,
    now_ms: int,
    take_profit_pct: float,
    portfolio: PortfolioState,
    open_sell_orders_by_tranche: Dict[int, Any],
    open_buy_indices: set,
    base_free_tracker: Optional[List[float]] = None,
) -> float:
    """Reconciles OPEN SELL and BUY orders on KuCoin, expiring stale BUY LIMIT orders."""
    open_rows = await conn.fetch(
        "SELECT * FROM orders WHERE bot_id = $1 AND status = 'OPEN' ORDER BY side DESC, created_at ASC;",
        bot_id,
    )

    reserved_buy_usdt = 0.0

    # 1. Reconcile OPEN SELL LIMIT orders first so profits & cash unlock immediately
    for ord_row in open_rows:
        if (ord_row["side"] or "").upper() != "SELL":
            continue
        ord_id = ord_row["id"]
        remote = await _fetch_order_safe(ex, ord_id, symbol)
        if not remote:
            continue

        metrics = _extract_fill_metrics(remote, symbol, DEFAULT_FEE_RATE)
        tranche_id = ord_row.get("tranche_id")
        tranche = next(
            (t for t in list(portfolio.active_tranches) if t.id == tranche_id),
            None,
        )
        if tranche is None and ord_row.get("tranche_index") is not None:
            t_idx = int(ord_row["tranche_index"])
            tranche = next(
                (t for t in list(portfolio.active_tranches) if t.tranche_index == t_idx),
                None,
            )

        if metrics["status"] == "closed" and metrics["filled"] > 0:
            await conn.execute(
                """
                UPDATE orders
                SET status = 'CLOSED', price = $1, amount = $2, fee = $3, filled_at = $4
                WHERE id = $5;
                """,
                float(metrics["avg_price"]),
                float(metrics["filled"]),
                float(metrics["fee_usdt"]),
                int(metrics["timestamp"] or now_ms),
                ord_id,
            )
            if tranche is not None:
                await _close_tranche_and_recycle(
                    conn=conn,
                    bot_id=bot_id,
                    symbol=symbol,
                    tranche=tranche,
                    exec_price=metrics["avg_price"],
                    filled_amount=metrics["filled"],
                    sell_fee=metrics["fee_usdt"],
                    sell_ts=metrics["timestamp"] or now_ms,
                    reason=ord_row.get("reason") or f"Take Profit Limit T{tranche.tranche_index}",
                    dry_run=False,
                    portfolio=portfolio,
                    ex=ex,
                    open_sell_orders_by_tranche=open_sell_orders_by_tranche,
                    base_free_tracker=base_free_tracker,
                )
        elif metrics["status"] == "canceled":
            await conn.execute("UPDATE orders SET status = 'CANCELED' WHERE id = $1;", ord_id)
            if tranche is not None and tranche.id is not None:
                open_sell_orders_by_tranche.pop(tranche.id, None)
                await conn.execute(
                    "UPDATE tranches SET sell_order_id = NULL WHERE id = $1;",
                    tranche.id,
                )
                if base_free_tracker is not None:
                    base_free_tracker[0] += float(ord_row["amount"] or tranche.amount)

    # 2. Reconcile OPEN BUY LIMIT orders (check fills and 1h-candle Variant A expiration)
    for ord_row in open_rows:
        if (ord_row["side"] or "").upper() != "BUY":
            continue
        ord_id = ord_row["id"]
        remote = await _fetch_order_safe(ex, ord_id, symbol)
        if not remote:
            reserved_buy_usdt += float(ord_row["price"] or 0.0) * float(ord_row["amount"] or 0.0) * (1.0 + DEFAULT_FEE_RATE)
            if ord_row.get("tranche_index") is not None:
                open_buy_indices.add(int(ord_row["tranche_index"]))
            continue

        metrics = _extract_fill_metrics(remote, symbol, DEFAULT_FEE_RATE)
        ord_idx = int(ord_row["tranche_index"]) if ord_row.get("tranche_index") is not None else 0
        ord_price = float(ord_row["price"] or metrics["limit_price"] or 0.0)
        stored_target = float(ord_row.get("target_sell_price") or 0.0)
        target_mult = (
            (stored_target / ord_price)
            if (stored_target > 0 and ord_price > 0)
            else (1.0 + take_profit_pct / 100.0)
        )
        ord_reason = ord_row.get("reason") or f"LIMIT T{ord_idx}"

        if metrics["status"] == "closed" and metrics["filled"] > 0:
            await _finalize_filled_buy_order(
                conn=conn,
                ex=ex,
                bot_id=bot_id,
                symbol=symbol,
                ord_id=ord_id,
                ord_idx=ord_idx,
                metrics=metrics,
                target_mult=target_mult,
                reason=ord_reason,
                now_ms=now_ms,
                portfolio=portfolio,
                open_sell_orders_by_tranche=open_sell_orders_by_tranche,
                base_free_tracker=base_free_tracker,
            )
            continue

        if metrics["status"] == "canceled":
            if metrics["filled"] > 0 and metrics["cost"] >= MIN_ORDER_NOTIONAL_USDT:
                await _finalize_filled_buy_order(
                    conn=conn,
                    ex=ex,
                    bot_id=bot_id,
                    symbol=symbol,
                    ord_id=ord_id,
                    ord_idx=ord_idx,
                    metrics=metrics,
                    target_mult=target_mult,
                    reason=f"{ord_reason} (parcial)",
                    now_ms=now_ms,
                    portfolio=portfolio,
                    open_sell_orders_by_tranche=open_sell_orders_by_tranche,
                    base_free_tracker=base_free_tracker,
                )
            else:
                await conn.execute("UPDATE orders SET status = 'CANCELED' WHERE id = $1;", ord_id)
            continue

        # Order is still OPEN on KuCoin: check Variant A expiration on new closed 1h candle
        ord_candle_ts = int(ord_row.get("candle_timestamp") or 0)
        if ord_candle_ts > 0 and latest_candle_ts > ord_candle_ts:
            final_state = await _cancel_order_safe(ex, ord_id, symbol)
            final_metrics = _extract_fill_metrics(final_state, symbol, DEFAULT_FEE_RATE)
            if final_metrics["filled"] > 0 and final_metrics["cost"] >= MIN_ORDER_NOTIONAL_USDT:
                await _finalize_filled_buy_order(
                    conn=conn,
                    ex=ex,
                    bot_id=bot_id,
                    symbol=symbol,
                    ord_id=ord_id,
                    ord_idx=ord_idx,
                    metrics=final_metrics,
                    target_mult=target_mult,
                    reason=f"{ord_reason} (parcial antes de expirar)",
                    now_ms=now_ms,
                    portfolio=portfolio,
                    open_sell_orders_by_tranche=open_sell_orders_by_tranche,
                    base_free_tracker=base_free_tracker,
                )
            else:
                await conn.execute("UPDATE orders SET status = 'CANCELED' WHERE id = $1;", ord_id)
                await conn.execute(
                    """
                    INSERT INTO bot_events (bot_id, event_type, details, timestamp)
                    VALUES ($1, 'ORDER_EXPIRED', $2, $3);
                    """,
                    bot_id,
                    f"Orden BUY LIMIT T{ord_idx} @ ${ord_price:.2f} expirada por cierre de nueva vela 1h",
                    int(now_ms),
                )
            continue

        # Still open within the valid candle window
        reserved_buy_usdt += ord_price * float(ord_row["amount"] or 0.0) * (1.0 + DEFAULT_FEE_RATE)
        open_buy_indices.add(ord_idx)

    return reserved_buy_usdt


async def _reconcile_kucoin_quote_balance(
    conn,
    ex,
    bot_id: str,
    symbol: str,
    budget: float,
    realized_profit_total: float,
    invested_usdt: float,
    active_buy_fees: float,
    deposited: float,
    withdrawn: float,
    reserved_open_buy_usdt: float,
    now_ms: int,
) -> Tuple[float, float, float, float]:
    """Reconciles real KuCoin subaccount quote/base balances against expected DB ledger.

    Returns (available_usdt, updated_deposited, updated_withdrawn, base_free).
    """
    base_coin, quote_coin = _split_symbol(symbol)
    try:
        bal = await ex.fetch_balance()
    except Exception as e:
        print(f"[BotSupervisor Balance Warn] {bot_id}: {e}")
        fallback_avail = max(
            0.0,
            budget
            + realized_profit_total
            - invested_usdt
            - active_buy_fees
            + deposited
            - withdrawn
            - reserved_open_buy_usdt,
        )
        return fallback_avail, deposited, withdrawn, 0.0

    quote_info = bal.get(quote_coin) or {}
    base_info = bal.get(base_coin) or {}
    kucoin_usdt_free = float(quote_info.get("free") or 0.0)
    kucoin_usdt_total = float(
        quote_info["total"] if quote_info.get("total") is not None else kucoin_usdt_free
    )
    kucoin_base_free = float(base_info.get("free") or 0.0)

    expected_total = max(
        0.0,
        budget + realized_profit_total - invested_usdt - active_buy_fees + deposited - withdrawn,
    )
    diff = kucoin_usdt_total - expected_total

    if abs(diff) > BALANCE_SYNC_THRESHOLD_USDT:
        tx_type = "DEPOSIT" if diff > 0 else "WITHDRAWAL"
        tx_amount = round(abs(diff), 6)
        if diff > 0:
            deposited += tx_amount
        else:
            withdrawn += tx_amount

        await conn.execute(
            """
            INSERT INTO capital_transactions (bot_id, type, amount, available_after, timestamp, reason)
            VALUES ($1, $2, $3, $4, $5, $6);
            """,
            bot_id,
            tx_type,
            tx_amount,
            round(kucoin_usdt_total, 6),
            int(now_ms),
            "Sincronización automática con saldo real de KuCoin",
        )
        await conn.execute(
            """
            INSERT INTO bot_events (bot_id, event_type, details, timestamp)
            VALUES ($1, 'CAPITAL_SYNC', $2, $3);
            """,
            bot_id,
            f"Ajuste automático por movimiento externo en KuCoin ({tx_type}: ${tx_amount:.2f} {quote_coin})",
            int(now_ms),
        )

    ledger_avail = max(
        0.0,
        budget
        + realized_profit_total
        - invested_usdt
        - active_buy_fees
        + deposited
        - withdrawn
        - reserved_open_buy_usdt,
    )
    return min(ledger_avail, kucoin_usdt_free), deposited, withdrawn, kucoin_base_free


def _build_strategy_and_cfg(
    bot_id: str,
    symbol: str,
    budget: float,
    cfg: Dict[str, Any],
) -> Tuple[BotConfigModel, BtcQuantumEvolutionRegimeStrategy, Optional[float]]:
    """Constructs the production strategy instance and config model from bot JSON settings."""
    base_weights = cfg.get("base_tranche_weights") or [0.30, 0.25, 0.20, 0.15, 0.10]
    floor_weights = cfg.get("floor_tranche_weights") or [0.40, 0.35, 0.25]
    base_max = int(cfg.get("base_max_tranches") or len(base_weights) or 5)
    extra_floor = int(
        cfg.get("extra_floor_tranches")
        if cfg.get("extra_floor_tranches") is not None
        else len(floor_weights)
    )
    all_weights = cfg.get("tranche_weights") or (
        list(base_weights[:base_max]) + list(floor_weights[:extra_floor])
    )

    bot_cfg = BotConfigModel(
        bot_id=bot_id,
        symbol=symbol,
        budget=budget,
        take_profit_pct=float(cfg.get("take_profit_pct", 4.5)),
        max_tranches=base_max + extra_floor,
        tranche_weights=all_weights,
        atr_multiplier=float(cfg.get("atr_multiplier", 1.5)),
        trailing_stop_pct=float(cfg.get("trailing_stop_pct", 1.4)),
        trend_weight=float(cfg.get("trend_weight", 0.70)),
        t0_rsi_threshold=float(cfg.get("t0_rsi_threshold", 48.0)),
        panic_rsi_threshold=float(cfg.get("panic_rsi_threshold", 28.0)),
    )

    prev_highest = cfg.get("trend_highest_price")
    strategy = BtcQuantumEvolutionRegimeStrategy(
        config=bot_cfg,
        enable_compounding=bool(cfg.get("enable_compounding", True)),
        macro_indicator=str(cfg.get("macro_indicator", "ema_daily_200")),
        trailing_stop_pct=bot_cfg.trailing_stop_pct,
        panic_rsi_threshold=bot_cfg.panic_rsi_threshold,
        trend_weight=bot_cfg.trend_weight,
        t0_rsi_threshold=bot_cfg.t0_rsi_threshold,
        base_max_tranches=base_max,
        extra_floor_tranches=extra_floor,
        floor_tranche_weights=floor_weights,
        trend_highest_price=float(prev_highest) if prev_highest is not None else None,
    )
    return bot_cfg, strategy, float(prev_highest) if prev_highest is not None else None


async def evaluate_running_bots(
    pool,
    exchange_factory: Optional[ExchangeFactory] = None,
) -> int:
    """Evaluates all RUNNING bots (both Paper Simulation and Live KuCoin Maker/Limit).

    Returns the count of active bots evaluated in this cycle.
    """
    ex_factory = exchange_factory or _create_subaccount_exchange

    async with pool.acquire() as conn:
        bot_table_exists = await conn.fetchval(
            "SELECT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'bots');"
        )
        if not bot_table_exists:
            return 0

        await _ensure_runtime_schema(conn)

        running_rows = await conn.fetch(
            "SELECT * FROM bots WHERE UPPER(status) = 'RUNNING' ORDER BY created_at ASC;"
        )
        if not running_rows:
            return 0

        candles_cache: Dict[str, pd.DataFrame] = {}

        for bot_row in running_rows:
            bot_id = bot_row["bot_id"]
            symbol = (bot_row["symbol"] or "BTC/USDT").strip().upper()
            budget = float(bot_row["budget"] or 1000.0)
            dry_run = bool(bot_row["dry_run"])
            raw_cfg = bot_row["config_json"]
            cfg: Dict[str, Any] = (
                json.loads(raw_cfg) if isinstance(raw_cfg, str) else (raw_cfg or {})
            )

            if symbol not in candles_cache:
                df_raw = await _load_hourly_candles_df(conn, symbol)
                candles_cache[symbol] = (
                    TechnicalIndicators.apply_all(df_raw) if not df_raw.empty else pd.DataFrame()
                )

            df_ind = candles_cache[symbol]
            if df_ind.empty:
                continue

            latest_row = df_ind.iloc[-1]
            latest_candle_ts = int(latest_row["timestamp"])
            now_ms = int(time.time() * 1000)

            # Hydrate tranches
            db_tranches = await conn.fetch(
                "SELECT * FROM tranches WHERE bot_id = $1 ORDER BY tranche_index ASC, id ASC;",
                bot_id,
            )
            active_tranches: List[TrancheModel] = []
            completed_tranches: List[TrancheModel] = []
            prev_highest_by_tranche: Dict[int, float] = {}
            sell_order_by_tranche_db: Dict[int, str] = {}
            realized_profit_total = 0.0

            for tr in db_tranches:
                st_str = (tr["status"] or "").upper()
                model = TrancheModel(
                    id=tr["id"],
                    bot_id=tr["bot_id"],
                    symbol=tr["symbol"],
                    tranche_index=int(tr["tranche_index"]),
                    allocated_budget=float(tr["allocated_budget"] or 0.0),
                    buy_price=float(tr["buy_price"] or 0.0),
                    amount=float(tr["amount"] or 0.0),
                    target_sell_price=float(tr["target_sell_price"] or 0.0),
                    status=(
                        TrancheStatus.ACTIVE
                        if st_str in ("ACTIVE", "ACTIVO", "OPEN")
                        else TrancheStatus.CLOSED
                    ),
                    buy_fee=float(tr["buy_fee"] or 0.0),
                    sell_fee=float(tr["sell_fee"] or 0.0),
                    buy_timestamp=tr["buy_timestamp"],
                    sell_timestamp=tr["sell_timestamp"],
                    profit_usdt=float(tr["profit_usdt"] or 0.0),
                    subsidized_satoshis=float(tr["subsidized_satoshis"] or 0.0),
                )
                if model.status == TrancheStatus.ACTIVE:
                    active_tranches.append(model)
                    if model.id is not None:
                        prev_highest_by_tranche[model.id] = float(tr.get("highest_price") or 0.0)
                        if tr.get("sell_order_id"):
                            sell_order_by_tranche_db[model.id] = str(tr["sell_order_id"])
                else:
                    completed_tranches.append(model)
                    realized_profit_total += model.profit_usdt

            # Hydrate capital transactions
            cap_rows = await conn.fetch(
                "SELECT type, COALESCE(SUM(amount), 0.0) AS total FROM capital_transactions WHERE bot_id = $1 GROUP BY type;",
                bot_id,
            )
            deposited = 0.0
            withdrawn = 0.0
            for c in cap_rows:
                t_type = (c["type"] or "").upper()
                if t_type == "DEPOSIT":
                    deposited += float(c["total"] or 0.0)
                elif t_type == "WITHDRAWAL":
                    withdrawn += float(c["total"] or 0.0)

            bot_cfg, strategy, prev_highest = _build_strategy_and_cfg(bot_id, symbol, budget, cfg)

            invested_usdt = sum(t.allocated_budget for t in active_tranches)
            active_buy_fees = sum(t.buy_fee for t in active_tranches)
            initial_avail = max(
                0.0,
                budget
                + realized_profit_total
                - invested_usdt
                - active_buy_fees
                + deposited
                - withdrawn,
            )

            portfolio = PortfolioState(
                symbol=symbol,
                total_budget=budget,
                available_usdt=initial_avail,
                active_tranches=active_tranches,
                completed_tranches=completed_tranches,
                total_realized_profit=realized_profit_total,
                total_withdrawn_amount=withdrawn,
                total_deposited_amount=deposited,
            )

            ex = None
            open_sell_orders_by_tranche: Dict[int, Any] = {}
            open_buy_indices: set = set()
            base_free_tracker = [0.0]

            try:
                if not dry_run:
                    try:
                        ex = await ex_factory(conn, cfg)
                    except Exception as e:
                        print(f"[BotSupervisor Live Connection Error] {bot_id}: {e}")
                        continue

                    # Seed map of already-open SELL orders so we know which tranches still need one
                    open_order_rows = await conn.fetch(
                        "SELECT * FROM orders WHERE bot_id = $1 AND status = 'OPEN';",
                        bot_id,
                    )
                    for row in open_order_rows:
                        if (row["side"] or "").upper() == "SELL" and row.get("tranche_id") is not None:
                            open_sell_orders_by_tranche[int(row["tranche_id"])] = dict(row)

                    # Fetch initial exchange balance so we know free base asset before Step L1/L2
                    try:
                        bal_init = await ex.fetch_balance()
                        base_coin = _split_symbol(symbol)[0]
                        base_free_tracker[0] = float((bal_init.get(base_coin) or {}).get("free") or 0.0)
                    except Exception:
                        base_free_tracker[0] = sum(t.amount for t in portfolio.active_tranches)

                    # L1. Reconcile existing OPEN orders (SELLs then BUYs + Variant A expiry)
                    reserved_buy_usdt = await _reconcile_live_open_orders(
                        conn=conn,
                        ex=ex,
                        bot_id=bot_id,
                        symbol=symbol,
                        latest_candle_ts=latest_candle_ts,
                        now_ms=now_ms,
                        take_profit_pct=bot_cfg.take_profit_pct,
                        portfolio=portfolio,
                        open_sell_orders_by_tranche=open_sell_orders_by_tranche,
                        open_buy_indices=open_buy_indices,
                        base_free_tracker=base_free_tracker,
                    )

                    # L2. Guarantee every ACTIVE tranche has a resting SELL LIMIT on KuCoin
                    for tr_model in list(portfolio.active_tranches):
                        if tr_model.id is not None and tr_model.id not in open_sell_orders_by_tranche:
                            # If DB sell_order_id pointed to a closed/missing order row, ensure clean resting limit
                            await _ensure_resting_sell_order(
                                conn=conn,
                                ex=ex,
                                bot_id=bot_id,
                                symbol=symbol,
                                tranche=tr_model,
                                now_ms=now_ms,
                                sell_amount=tr_model.amount,
                                dry_run=False,
                                portfolio=portfolio,
                                open_sell_orders_by_tranche=open_sell_orders_by_tranche,
                                base_free_tracker=base_free_tracker,
                            )

                    # Recompute invested/fees after L1/L2 fills
                    invested_usdt = sum(t.allocated_budget for t in portfolio.active_tranches)
                    active_buy_fees = sum(t.buy_fee for t in portfolio.active_tranches)

                    # L3. Reconcile real KuCoin USDT balance against DB ledger
                    (
                        live_avail_usdt,
                        deposited,
                        withdrawn,
                        kucoin_base_free,
                    ) = await _reconcile_kucoin_quote_balance(
                        conn=conn,
                        ex=ex,
                        bot_id=bot_id,
                        symbol=symbol,
                        budget=budget,
                        realized_profit_total=portfolio.total_realized_profit,
                        invested_usdt=invested_usdt,
                        active_buy_fees=active_buy_fees,
                        deposited=deposited,
                        withdrawn=withdrawn,
                        reserved_open_buy_usdt=reserved_buy_usdt,
                        now_ms=now_ms,
                    )
                    base_free_tracker[0] = kucoin_base_free
                    portfolio.available_usdt = live_avail_usdt
                    portfolio.total_deposited_amount = deposited
                    portfolio.total_withdrawn_amount = withdrawn

                # Compute leak-free post-buy price extremes
                curr_close = round(float(latest_row.get("close") or 0.0), 4)
                latest_high = float(latest_row.get("high") or curr_close)
                latest_low = float(latest_row.get("low") or curr_close)

                if portfolio.active_tranches:
                    oldest_buy_ts = min(int(t.buy_timestamp or 0) for t in portfolio.active_tranches)
                    newest_buy_ts = max(int(t.buy_timestamp or 0) for t in portfolio.active_tranches)
                    post_high, post_low = await _get_post_buy_extremes(
                        conn=conn,
                        symbol=symbol,
                        since_ms=newest_buy_ts if dry_run else oldest_buy_ts,
                        latest_candle_ts=latest_candle_ts,
                        latest_row_high=latest_high,
                        latest_row_low=latest_low,
                        fallback_price=curr_close,
                    )
                    for tr_model in portfolio.active_tranches:
                        if tr_model.id is None:
                            continue
                        prev_tr_high = prev_highest_by_tranche.get(tr_model.id, 0.0)
                        new_tr_high = max(prev_tr_high, tr_model.buy_price, post_high)
                        if abs(new_tr_high - prev_tr_high) > 1e-4:
                            await conn.execute(
                                "UPDATE tranches SET highest_price = $1 WHERE id = $2;",
                                new_tr_high,
                                tr_model.id,
                            )
                else:
                    post_high, post_low = latest_high, latest_low

                detected_regime = MarketRegimeDetector.detect_regime(latest_row).value
                curr_rsi = round(float(latest_row.get("rsi_14") or 50.0), 2)

                eval_row = latest_row.copy()
                eval_row["high"] = post_high
                eval_row["low"] = post_low

                signals = strategy.evaluate(eval_row, portfolio)

                cfg_dirty = False
                if strategy.trend_highest_price != prev_highest:
                    cfg["trend_highest_price"] = strategy.trend_highest_price
                    cfg_dirty = True
                if (
                    cfg.get("last_regime") != detected_regime
                    or cfg.get("last_rsi") != curr_rsi
                    or cfg.get("last_price") != curr_close
                ):
                    cfg["last_regime"] = detected_regime
                    cfg["last_rsi"] = curr_rsi
                    cfg["last_price"] = curr_close
                    cfg_dirty = True

                if cfg_dirty:
                    await conn.execute(
                        "UPDATE bots SET config_json = $1, updated_at = $2 WHERE bot_id = $3;",
                        json.dumps(cfg),
                        now_ms,
                        bot_id,
                    )

                # Process SELL signals (Trailing Stop in Live; TP + Trailing Stop in Simulation)
                for sig in signals:
                    if sig.signal_type != SignalType.SELL_TRANCHE or sig.tranche_ref is None:
                        continue
                    tranche = sig.tranche_ref
                    is_trailing = "Trailing Stop" in (sig.reason or "")

                    if not dry_run:
                        # Resting SELL LIMIT orders handle Take Profit in Live mode
                        if not is_trailing:
                            continue

                        # 1) Cancel any resting SELL LIMIT on KuCoin before stopping at market
                        open_sell = (
                            open_sell_orders_by_tranche.get(tranche.id)
                            if tranche.id is not None
                            else None
                        )
                        if open_sell is not None:
                            cancel_res = await _cancel_order_safe(ex, open_sell["id"], symbol)
                            cancel_metrics = _extract_fill_metrics(
                                cancel_res, symbol, DEFAULT_FEE_RATE
                            )
                            if cancel_metrics["status"] == "closed" and cancel_metrics["filled"] > 0:
                                await conn.execute(
                                    """
                                    UPDATE orders
                                    SET status = 'CLOSED', price = $1, amount = $2, fee = $3, filled_at = $4
                                    WHERE id = $5;
                                    """,
                                    float(cancel_metrics["avg_price"]),
                                    float(cancel_metrics["filled"]),
                                    float(cancel_metrics["fee_usdt"]),
                                    int(cancel_metrics["timestamp"] or now_ms),
                                    open_sell["id"],
                                )
                                await _close_tranche_and_recycle(
                                    conn=conn,
                                    bot_id=bot_id,
                                    symbol=symbol,
                                    tranche=tranche,
                                    exec_price=cancel_metrics["avg_price"],
                                    filled_amount=cancel_metrics["filled"],
                                    sell_fee=cancel_metrics["fee_usdt"],
                                    sell_ts=cancel_metrics["timestamp"] or now_ms,
                                    reason=f"Take Profit Limit T{tranche.tranche_index}",
                                    dry_run=False,
                                    portfolio=portfolio,
                                    ex=ex,
                                    open_sell_orders_by_tranche=open_sell_orders_by_tranche,
                                    base_free_tracker=base_free_tracker,
                                )
                                continue

                            await conn.execute(
                                "UPDATE orders SET status = 'CANCELED' WHERE id = $1;",
                                open_sell["id"],
                            )
                            open_sell_orders_by_tranche.pop(tranche.id, None)
                            base_free_tracker[0] += float(open_sell.get("amount") or tranche.amount)

                        # 2) Execute STOP_MARKET exit on KuCoin
                        try:
                            sell_amt = min(tranche.amount, base_free_tracker[0]) if base_free_tracker[0] > 0 else tranche.amount
                            stop_res = await _place_market_sell_order(ex, symbol, sell_amt)
                            if stop_res and not stop_res.get("average") and stop_res.get("id"):
                                stop_res = (
                                    await _fetch_order_safe(ex, str(stop_res["id"]), symbol)
                                    or stop_res
                                )
                            stop_metrics = _extract_fill_metrics(stop_res, symbol, DEFAULT_FEE_RATE)
                            exec_price = stop_metrics["avg_price"] or float(sig.price) * (1.0 - STOP_SLIPPAGE)
                            filled_amt = stop_metrics["filled"] or sell_amt
                            sell_fee = stop_metrics["fee_usdt"] or (filled_amt * exec_price * DEFAULT_FEE_RATE)
                            stop_ord_id = str(
                                (stop_res or {}).get("id")
                                or f"live_stop_{bot_id}_T{tranche.tranche_index}_{uuid.uuid4().hex[:8]}"
                            )
                            await _record_order_row(
                                conn,
                                order_id=stop_ord_id,
                                bot_id=bot_id,
                                symbol=symbol,
                                side="SELL",
                                order_type="STOP_MARKET",
                                price=exec_price,
                                amount=filled_amt,
                                status="CLOSED",
                                fee=sell_fee,
                                created_at=now_ms,
                                filled_at=stop_metrics["timestamp"] or now_ms,
                                tranche_index=tranche.tranche_index,
                                tranche_id=tranche.id,
                                reason=sig.reason,
                            )
                            base_free_tracker[0] = max(0.0, base_free_tracker[0] - filled_amt)
                            await _close_tranche_and_recycle(
                                conn=conn,
                                bot_id=bot_id,
                                symbol=symbol,
                                tranche=tranche,
                                exec_price=exec_price,
                                filled_amount=filled_amt,
                                sell_fee=sell_fee,
                                sell_ts=stop_metrics["timestamp"] or now_ms,
                                reason=sig.reason,
                                dry_run=False,
                                portfolio=portfolio,
                                ex=ex,
                                open_sell_orders_by_tranche=open_sell_orders_by_tranche,
                                base_free_tracker=base_free_tracker,
                            )
                        except Exception as e:
                            print(f"[BotSupervisor Live Trailing Stop Error] {bot_id}: {e}")
                            continue
                    else:
                        # Simulation (Paper) exit: verify against strictly post-buy ticks for this specific tranche
                        if tranche.buy_timestamp is not None:
                            tr_high, tr_low = await _get_post_buy_extremes(
                                conn=conn,
                                symbol=symbol,
                                since_ms=int(tranche.buy_timestamp),
                                latest_candle_ts=latest_candle_ts,
                                latest_row_high=latest_high,
                                latest_row_low=latest_low,
                                fallback_price=tranche.buy_price,
                            )
                            if is_trailing and tr_low > float(sig.price):
                                continue
                            if not is_trailing and tr_high < tranche.target_sell_price:
                                continue

                        nominal_price = float(sig.price)
                        exec_price = (
                            nominal_price * (1.0 - STOP_SLIPPAGE)
                            if is_trailing
                            else nominal_price
                        )
                        sell_fee = tranche.amount * exec_price * DEFAULT_FEE_RATE
                        order_id = f"sim_sell_{bot_id}_T{tranche.tranche_index}_{uuid.uuid4().hex[:8]}"
                        await _record_order_row(
                            conn,
                            order_id=order_id,
                            bot_id=bot_id,
                            symbol=symbol,
                            side="SELL",
                            order_type="STOP_MARKET" if is_trailing else "LIMIT",
                            price=exec_price,
                            amount=tranche.amount,
                            status="CLOSED",
                            fee=sell_fee,
                            created_at=now_ms,
                            filled_at=now_ms,
                            tranche_index=tranche.tranche_index,
                            tranche_id=tranche.id,
                            reason=sig.reason,
                        )
                        await _close_tranche_and_recycle(
                            conn=conn,
                            bot_id=bot_id,
                            symbol=symbol,
                            tranche=tranche,
                            exec_price=exec_price,
                            filled_amount=tranche.amount,
                            sell_fee=sell_fee,
                            sell_ts=now_ms,
                            reason=sig.reason,
                            dry_run=True,
                            portfolio=portfolio,
                        )

                # Process BUY signals
                for sig in signals:
                    if sig.signal_type != SignalType.BUY_TRANCHE:
                        continue
                    tr_idx = int(sig.tranche_index)
                    already_active = any(
                        t.tranche_index == tr_idx and t.status == TrancheStatus.ACTIVE
                        for t in portfolio.active_tranches
                    )
                    if already_active or (not dry_run and tr_idx in open_buy_indices):
                        continue

                    cost = float(sig.allocated_usdt)
                    buy_fee = cost * DEFAULT_FEE_RATE
                    if (
                        portfolio.available_usdt < (cost + buy_fee)
                        and portfolio.available_usdt >= MIN_ORDER_NOTIONAL_USDT * (1.0 + DEFAULT_FEE_RATE)
                    ):
                        cost = portfolio.available_usdt / (1.0 + DEFAULT_FEE_RATE)
                        buy_fee = cost * DEFAULT_FEE_RATE

                    if cost < MIN_ORDER_NOTIONAL_USDT or portfolio.available_usdt < (cost + buy_fee) * 0.999:
                        continue

                    limit_price = float(sig.price)
                    target_mult = (
                        (float(sig.target_sell_price) / limit_price)
                        if (sig.target_sell_price and limit_price > 0)
                        else (1.0 + bot_cfg.take_profit_pct / 100.0)
                    )

                    if dry_run:
                        est_amount = cost / limit_price
                        target_sell = limit_price * target_mult
                        new_tranche = await _activate_tranche(
                            conn=conn,
                            bot_id=bot_id,
                            symbol=symbol,
                            tranche_index=tr_idx,
                            cost=cost,
                            exec_price=limit_price,
                            amount=est_amount,
                            target_sell=target_sell,
                            buy_fee=buy_fee,
                            buy_ts=now_ms,
                            reason=sig.reason,
                            dry_run=True,
                            portfolio=portfolio,
                        )
                        order_id = f"sim_buy_{bot_id}_T{tr_idx}_{uuid.uuid4().hex[:8]}"
                        await _record_order_row(
                            conn,
                            order_id=order_id,
                            bot_id=bot_id,
                            symbol=symbol,
                            side="BUY",
                            order_type="LIMIT",
                            price=limit_price,
                            amount=est_amount,
                            status="CLOSED",
                            fee=buy_fee,
                            created_at=now_ms,
                            filled_at=now_ms,
                            tranche_index=tr_idx,
                            tranche_id=new_tranche.id,
                            candle_timestamp=latest_candle_ts,
                            target_sell_price=target_sell,
                            reason=sig.reason,
                        )
                    else:
                        try:
                            fmt_price = _format_precision_price(ex, symbol, limit_price)
                            fmt_amount = _format_precision_amount(ex, symbol, cost / fmt_price)
                            if fmt_amount <= 0 or fmt_amount * fmt_price < MIN_ORDER_NOTIONAL_USDT:
                                continue

                            placed = await _place_limit_order(
                                ex, symbol, "buy", fmt_amount, fmt_price
                            )
                            ord_id = str(placed["id"])
                            latest_ord = placed
                            if (placed.get("status") or "").lower() not in ("closed", "filled"):
                                fetched = await _fetch_order_safe(ex, ord_id, symbol)
                                if fetched:
                                    latest_ord = fetched

                            metrics = _extract_fill_metrics(latest_ord, symbol, DEFAULT_FEE_RATE)

                            if metrics["status"] == "closed" and metrics["filled"] > 0:
                                await _record_order_row(
                                    conn,
                                    order_id=ord_id,
                                    bot_id=bot_id,
                                    symbol=symbol,
                                    side="BUY",
                                    order_type="LIMIT",
                                    price=metrics["avg_price"],
                                    amount=metrics["filled"],
                                    status="CLOSED",
                                    fee=metrics["fee_usdt"],
                                    created_at=now_ms,
                                    filled_at=metrics["timestamp"] or now_ms,
                                    tranche_index=tr_idx,
                                    candle_timestamp=latest_candle_ts,
                                    target_sell_price=metrics["avg_price"] * target_mult,
                                    reason=sig.reason,
                                )
                                new_tranche = await _activate_tranche(
                                    conn=conn,
                                    bot_id=bot_id,
                                    symbol=symbol,
                                    tranche_index=tr_idx,
                                    cost=metrics["cost"],
                                    exec_price=metrics["avg_price"],
                                    amount=metrics["filled"],
                                    target_sell=metrics["avg_price"] * target_mult,
                                    buy_fee=metrics["fee_usdt"],
                                    buy_ts=metrics["timestamp"] or now_ms,
                                    reason=sig.reason,
                                    dry_run=False,
                                    portfolio=portfolio,
                                )
                                await conn.execute(
                                    "UPDATE orders SET tranche_id = $1 WHERE id = $2;",
                                    new_tranche.id,
                                    ord_id,
                                )
                                base_free_tracker[0] += metrics["filled"]
                                await _ensure_resting_sell_order(
                                    conn=conn,
                                    ex=ex,
                                    bot_id=bot_id,
                                    symbol=symbol,
                                    tranche=new_tranche,
                                    now_ms=now_ms,
                                    sell_amount=new_tranche.amount,
                                    dry_run=False,
                                    portfolio=portfolio,
                                    open_sell_orders_by_tranche=open_sell_orders_by_tranche,
                                    base_free_tracker=base_free_tracker,
                                )
                            else:
                                sig_target = float(
                                    sig.target_sell_price or (fmt_price * target_mult)
                                )
                                await _record_order_row(
                                    conn,
                                    order_id=ord_id,
                                    bot_id=bot_id,
                                    symbol=symbol,
                                    side="BUY",
                                    order_type="LIMIT",
                                    price=fmt_price,
                                    amount=fmt_amount,
                                    status="OPEN",
                                    fee=0.0,
                                    created_at=now_ms,
                                    filled_at=None,
                                    tranche_index=tr_idx,
                                    candle_timestamp=latest_candle_ts,
                                    target_sell_price=sig_target,
                                    reason=sig.reason,
                                )
                                await conn.execute(
                                    """
                                    INSERT INTO bot_events (bot_id, event_type, details, timestamp)
                                    VALUES ($1, 'ORDER_PLACED', $2, $3);
                                    """,
                                    bot_id,
                                    f"Orden BUY LIMIT T{tr_idx} colocada @ ${fmt_price:.2f} ({fmt_amount * fmt_price:.2f} USDT | {sig.reason})",
                                    now_ms,
                                )
                                open_buy_indices.add(tr_idx)
                                reserved = fmt_price * fmt_amount * (1.0 + DEFAULT_FEE_RATE)
                                portfolio.available_usdt = max(0.0, portfolio.available_usdt - reserved)
                                print(
                                    f"[BotSupervisor] 📌 {bot_id} BUY LIMIT resting T{tr_idx} "
                                    f"{fmt_amount} @ ${fmt_price:.2f} (id={ord_id})"
                                )
                        except Exception as e:
                            print(f"[BotSupervisor Live Buy Error] {bot_id}: {e}")
                            continue
            finally:
                if ex is not None:
                    await ex.close()

        return len(running_rows)


async def update_supervisor_heartbeat(pool, details: dict) -> None:
    """Updates the bot_supervisor liveness heartbeat in system_heartbeat."""
    try:
        async with pool.acquire() as conn:
            await conn.execute(
                """
                INSERT INTO system_heartbeat (service_name, last_heartbeat, status, details)
                VALUES ('bot_supervisor', NOW(), 'running', $1::jsonb)
                ON CONFLICT (service_name)
                DO UPDATE SET last_heartbeat = NOW(), status = 'running', details = EXCLUDED.details;
                """,
                json.dumps(details),
            )
    except Exception as e:
        print(f"[BotSupervisor Heartbeat Warn] {e}")


async def run_bot_supervisor() -> None:
    """Autonomous 24/7 daemon supervising and executing quantitative spot bots."""
    print("Iniciando CryptoView Bot Supervisor Autónomo 24/7...")
    pool = await init_db_pool()

    try:
        while True:
            start_ts = time.time()
            evaluated_count = 0
            try:
                evaluated_count = await evaluate_running_bots(pool)
            except Exception as e:
                print(f"[BotSupervisor Error] Cycle exception: {e}")

            duration_ms = int((time.time() - start_ts) * 1000)

            await update_supervisor_heartbeat(
                pool,
                {
                    "running_bots_evaluated": evaluated_count,
                    "cycle_duration_ms": duration_ms,
                    "timestamp_utc": datetime.now(timezone.utc).isoformat(),
                },
            )

            sleep_sec = max(5, settings.BOT_SUPERVISOR_INTERVAL_SECONDS)
            await asyncio.sleep(sleep_sec)
    except (KeyboardInterrupt, asyncio.CancelledError):
        print("Deteniendo Bot Supervisor...")
    finally:
        await close_db_pool()


if __name__ == "__main__":
    asyncio.run(run_bot_supervisor())
