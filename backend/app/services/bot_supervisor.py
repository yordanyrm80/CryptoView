import asyncio
from datetime import datetime, timezone
import json
import time
import uuid
from enum import Enum
from typing import Any, Dict, List, Optional
import httpx
import numpy as np
import pandas as pd
import ccxt.async_support as ccxt
from app.config import settings
from app.database import init_db_pool, close_db_pool
from app.services.crypto import decrypt_secret


from app.strategies import (
    MarketRegime,
    TrancheStatus,
    SignalType,
    TrancheModel,
    BotConfigModel,
    ActionSignal,
    PortfolioState,
    TechnicalIndicators,
    MarketRegimeDetector,
    BtcQuantumEvolutionRegimeStrategy,
)

DEFAULT_DISCORD_WEBHOOK_URL = settings.DISCORD_WEBHOOK_URL.strip() if settings.DISCORD_WEBHOOK_URL else ""


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
    try:
        url = DEFAULT_DISCORD_WEBHOOK_URL
        notify_buys = True
        notify_sells = True
        notify_plateau = True

        row = await conn.fetchrow("SELECT value_json FROM system_settings WHERE key = 'bot_notifications';")
        if row and row["value_json"]:
            cfg = json.loads(row["value_json"]) if isinstance(row["value_json"], str) else row["value_json"]
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

        from datetime import datetime, timezone

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
        row = await conn.fetchrow("SELECT value_json FROM system_settings WHERE key = 'exchange_proxy';")
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
        print(f"[BotSupervisor Proxy Warning] Error al leer proxy de BD: {e}")
        return getattr(settings, "KUCOIN_PROXY_URL", None) or None


async def _execute_subaccount_market_order(
    conn,
    cfg: Dict[str, Any],
    symbol: str,
    side: str,
    amount: float,
) -> Optional[Dict[str, Any]]:
    """Executes an order on the bot's isolated KuCoin subaccount when dry_run=False."""
    raw_key = (cfg.get("api_key") or "").strip()
    raw_secret = (cfg.get("api_secret") or "").strip()
    raw_pass = (cfg.get("api_passphrase") or "").strip()

    api_key = decrypt_secret(raw_key) or raw_key
    api_secret = decrypt_secret(raw_secret) or raw_secret
    api_pass = decrypt_secret(raw_pass) or raw_pass

    if not (api_key and api_secret and api_pass):
        raise ValueError("Missing dedicated subaccount credentials for LIVE execution.")

    exchange_params = {
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
        formatted_amount = float(ex.amount_to_precision(symbol, amount))
        return await ex.create_order(symbol=symbol, type="market", side=side, amount=formatted_amount)
    finally:
        await ex.close()


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

    # Reverse to chronological order (oldest -> newest)
    records = [dict(r) for r in reversed(rows)]
    return pd.DataFrame(records)


async def evaluate_running_bots(pool) -> int:
    """
    Evaluates all bots with status == 'RUNNING' (both Simulación/Paper and En Vivo).
    Returns the number of active bots evaluated in this cycle.
    """
    fee_rate = 0.001
    stop_slippage = 0.0005
    recycle_profit_fraction = 0.35
    max_subsidized_discount_pct = 0.12

    async with pool.acquire() as conn:
        bot_Table_exists = await conn.fetchval(
            "SELECT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'bots');"
        )
        if not bot_Table_exists:
            return 0

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
            cfg: Dict[str, Any] = json.loads(raw_cfg) if isinstance(raw_cfg, str) else (raw_cfg or {})

            if symbol not in candles_cache:
                df_raw = await _load_hourly_candles_df(conn, symbol)
                if not df_raw.empty:
                    candles_cache[symbol] = TechnicalIndicators.apply_all(df_raw)
                else:
                    candles_cache[symbol] = pd.DataFrame()

            df_ind = candles_cache[symbol]
            if df_ind.empty:
                continue

            latest_row = df_ind.iloc[-1]
            now_ms = int(time.time() * 1000)

            await conn.execute(
                "ALTER TABLE tranches ADD COLUMN IF NOT EXISTS highest_price DOUBLE PRECISION DEFAULT 0.0;"
            )

            # Hydrate tranches
            db_tranches = await conn.fetch(
                "SELECT * FROM tranches WHERE bot_id = $1 ORDER BY tranche_index ASC, id ASC;",
                bot_id,
            )
            active_tranches: List[TrancheModel] = []
            completed_tranches: List[TrancheModel] = []
            realized_profit_total = 0.0
            invested_usdt = 0.0
            active_buy_fees = 0.0

            # Real-time tick lookup: allows resting Limit Take Profit / Trailing Stop to fill in real time
            latest_tick = await conn.fetchrow(
                """
                SELECT high, low, close
                FROM market_candles
                WHERE exchange = 'kucoin' AND symbol = $1
                ORDER BY time DESC
                LIMIT 1;
                """,
                symbol,
            )
            live_high = float(latest_tick["high"]) if latest_tick else float(latest_row.get("high") or 0.0)
            live_low = float(latest_tick["low"]) if latest_tick else float(latest_row.get("low") or 0.0)
            candle_high = max(float(latest_row.get("high") or 0.0), live_high)

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
                    status=TrancheStatus.ACTIVE if st_str in ("ACTIVE", "ACTIVO", "OPEN") else TrancheStatus.CLOSED,
                    buy_fee=float(tr["buy_fee"] or 0.0),
                    sell_fee=float(tr["sell_fee"] or 0.0),
                    buy_timestamp=tr["buy_timestamp"],
                    sell_timestamp=tr["sell_timestamp"],
                    profit_usdt=float(tr["profit_usdt"] or 0.0),
                    subsidized_satoshis=float(tr["subsidized_satoshis"] or 0.0),
                )
                if model.status == TrancheStatus.ACTIVE:
                    active_tranches.append(model)
                    invested_usdt += model.allocated_budget
                    active_buy_fees += model.buy_fee
                    prev_tr_high = float(tr.get("highest_price") or 0.0)
                    new_tr_high = max(prev_tr_high, model.buy_price, candle_high)
                    if abs(new_tr_high - prev_tr_high) > 1e-4:
                        await conn.execute(
                            "UPDATE tranches SET highest_price = $1 WHERE id = $2;",
                            new_tr_high,
                            model.id,
                        )
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

            available_usdt = max(0.0, budget + realized_profit_total - invested_usdt - active_buy_fees) + (deposited - withdrawn)

            base_weights = cfg.get("base_tranche_weights") or [0.30, 0.25, 0.20, 0.15, 0.10]
            floor_weights = cfg.get("floor_tranche_weights") or [0.40, 0.35, 0.25]
            base_max = int(cfg.get("base_max_tranches") or len(base_weights) or 5)
            extra_floor = int(
                cfg.get("extra_floor_tranches")
                if cfg.get("extra_floor_tranches") is not None
                else len(floor_weights)
            )
            all_weights = cfg.get("tranche_weights") or (list(base_weights[:base_max]) + list(floor_weights[:extra_floor]))

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

            portfolio = PortfolioState(
                symbol=symbol,
                total_budget=budget,
                available_usdt=available_usdt,
                active_tranches=active_tranches,
                completed_tranches=completed_tranches,
                total_realized_profit=realized_profit_total,
                total_withdrawn_amount=withdrawn,
                total_deposited_amount=deposited,
            )

            detected_regime = MarketRegimeDetector.detect_regime(latest_row).value
            curr_rsi = round(float(latest_row.get("rsi_14") or 50.0), 2)
            curr_close = round(float(latest_row.get("close") or 0.0), 4)

            # Create evaluation row: indicators and close are 100% based on the COMPLETED 1h candle.
            # Intrabar high and low are updated to allow resting TP fills, but close is strictly completed 1h close.
            eval_row = latest_row.copy()
            eval_row["high"] = candle_high
            eval_row["low"] = min(float(latest_row.get("low") or 0.0), live_low)

            signals = strategy.evaluate(eval_row, portfolio)

            # Persist updated trend_highest_price and live market regime / RSI
            cfg_dirty = False
            if strategy.trend_highest_price != prev_highest:
                cfg["trend_highest_price"] = strategy.trend_highest_price
                cfg_dirty = True
            if cfg.get("last_regime") != detected_regime or cfg.get("last_rsi") != curr_rsi:
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

            # 1. Process SELL signals first
            for sig in signals:
                if sig.signal_type == SignalType.SELL_TRANCHE and sig.tranche_ref is not None:
                    tranche = sig.tranche_ref
                    nominal_price = float(sig.price)
                    is_trailing = "Trailing Stop" in (sig.reason or "")
                    exec_price = nominal_price * (1.0 - stop_slippage) if is_trailing else nominal_price

                    if not dry_run:
                        try:
                            order_res = await _execute_subaccount_market_order(
                                conn, cfg, symbol, "sell", tranche.amount
                            )
                            if order_res and order_res.get("average"):
                                exec_price = float(order_res["average"])
                        except Exception as e:
                            print(f"[BotSupervisor Live Sell Error] {bot_id}: {e}")
                            continue

                    revenue_gross = tranche.amount * exec_price
                    sell_fee = revenue_gross * fee_rate
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
                            profit_usdt = $4
                        WHERE id = $5;
                        """,
                        exec_price,
                        sell_fee,
                        now_ms,
                        realized_profit,
                        tranche.id,
                    )

                    order_id = f"{'sim' if dry_run else 'live'}_sell_{bot_id}_T{tranche.tranche_index}_{uuid.uuid4().hex[:8]}"
                    await conn.execute(
                        """
                        INSERT INTO orders (id, bot_id, symbol, side, order_type, price, amount, status, fee, created_at, filled_at)
                        VALUES ($1, $2, $3, 'SELL', 'LIMIT', $4, $5, 'CLOSED', $6, $7, $7);
                        """,
                        order_id,
                        bot_id,
                        symbol,
                        exec_price,
                        tranche.amount,
                        sell_fee,
                        now_ms,
                    )

                    await conn.execute(
                        """
                        INSERT INTO bot_events (bot_id, event_type, details, timestamp)
                        VALUES ($1, 'SELL', $2, $3);
                        """,
                        bot_id,
                        f"Venta ejecutada T{tranche.tranche_index} @ ${exec_price:.2f} ({sig.reason}). Beneficio: {realized_profit:+.2f} USDT",
                        now_ms,
                    )

                    if tranche in portfolio.active_tranches:
                        portfolio.active_tranches.remove(tranche)
                    portfolio.available_usdt += revenue_net
                    portfolio.total_realized_profit += realized_profit

                    # Cascading Subsidized Profit Recycling (35% profit cut down to -12% floor)
                    if realized_profit > 0 and portfolio.active_tranches:
                        remaining_discount = realized_profit * recycle_profit_fraction
                        hung_tranches = [
                            t for t in portfolio.active_tranches if t.buy_price > tranche.buy_price
                        ]
                        hung_tranches.sort(key=lambda t: t.buy_price, reverse=True)
                        for hung in hung_tranches:
                            if remaining_discount <= 0.001:
                                break
                            floor_min = hung.buy_price * (1.0 - max_subsidized_discount_pct)
                            max_reduction = hung.target_sell_price - floor_min
                            if max_reduction <= 0:
                                continue
                            max_absorbable_usdt = max_reduction * hung.amount
                            apply_discount = min(remaining_discount, max_absorbable_usdt)
                            hung.target_sell_price -= apply_discount / hung.amount
                            hung.subsidized_satoshis += apply_discount
                            remaining_discount -= apply_discount
                            await conn.execute(
                                """
                                UPDATE tranches
                                SET target_sell_price = $1, subsidized_satoshis = $2
                                WHERE id = $3;
                                """,
                                hung.target_sell_price,
                                hung.subsidized_satoshis,
                                hung.id,
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
                            {"name": "Estado / Motivo", "value": f"`{sig.reason}`", "inline": True},
                        ],
                        footer_text=f"{bot_id} • Cash Flow Realizado",
                    )
                    mode_tag = "SIMULACIÓN" if dry_run else "EN VIVO"
                    print(
                        f"[BotSupervisor] 💰 {bot_id} ({mode_tag}) SELL T{tranche.tranche_index} @ ${exec_price:.2f} | Profit: {realized_profit:+.2f} USDT"
                    )

            # 2. Process BUY signals second
            for sig in signals:
                if sig.signal_type == SignalType.BUY_TRANCHE:
                    already_active = any(
                        t.tranche_index == sig.tranche_index and t.status == TrancheStatus.ACTIVE
                        for t in portfolio.active_tranches
                    )
                    if already_active:
                        continue

                    cost = float(sig.allocated_usdt)
                    buy_fee = cost * fee_rate
                    if portfolio.available_usdt < (cost + buy_fee) and portfolio.available_usdt >= 10.0:
                        cost = portfolio.available_usdt / (1.0 + fee_rate)
                        buy_fee = cost * fee_rate

                    if cost < 10.0 or portfolio.available_usdt < cost:
                        continue

                    exec_price = float(sig.price)
                    amount = cost / exec_price

                    if not dry_run:
                        try:
                            order_res = await _execute_subaccount_market_order(
                                conn, cfg, symbol, "buy", amount
                            )
                            if order_res and order_res.get("average"):
                                exec_price = float(order_res["average"])
                                amount = cost / exec_price
                        except Exception as e:
                            print(f"[BotSupervisor Live Buy Error] {bot_id}: {e}")
                            continue

                    target_sell = float(
                        sig.target_sell_price
                        or (exec_price * (1.0 + bot_cfg.take_profit_pct / 100.0))
                    )

                    new_id = await conn.fetchval(
                        """
                        INSERT INTO tranches (
                            bot_id, symbol, tranche_index, allocated_budget, buy_price, amount,
                            target_sell_price, highest_price, status, buy_fee, buy_timestamp, profit_usdt, subsidized_satoshis
                        )
                        VALUES ($1, $2, $3, $4, $5, $6, $7, $5, 'ACTIVE', $8, $9, 0.0, 0.0)
                        RETURNING id;
                        """,
                        bot_id,
                        symbol,
                        int(sig.tranche_index),
                        cost,
                        exec_price,
                        amount,
                        target_sell,
                        buy_fee,
                        now_ms,
                    )

                    order_id = f"{'sim' if dry_run else 'live'}_buy_{bot_id}_T{sig.tranche_index}_{uuid.uuid4().hex[:8]}"
                    await conn.execute(
                        """
                        INSERT INTO orders (id, bot_id, symbol, side, order_type, price, amount, status, fee, created_at, filled_at)
                        VALUES ($1, $2, $3, 'BUY', 'LIMIT', $4, $5, 'CLOSED', $6, $7, $7);
                        """,
                        order_id,
                        bot_id,
                        symbol,
                        exec_price,
                        amount,
                        buy_fee,
                        now_ms,
                    )

                    await conn.execute(
                        """
                        INSERT INTO bot_events (bot_id, event_type, details, timestamp)
                        VALUES ($1, 'BUY', $2, $3);
                        """,
                        bot_id,
                        f"Compra ejecutada T{sig.tranche_index} @ ${exec_price:.2f} ({cost:.2f} USDT) -> Objetivo TP: ${target_sell:.2f} ({sig.reason})",
                        now_ms,
                    )

                    portfolio.available_usdt -= (cost + buy_fee)
                    portfolio.active_tranches.append(
                        TrancheModel(
                            id=new_id,
                            bot_id=bot_id,
                            symbol=symbol,
                            tranche_index=int(sig.tranche_index),
                            allocated_budget=cost,
                            buy_price=exec_price,
                            amount=amount,
                            target_sell_price=target_sell,
                            status=TrancheStatus.ACTIVE,
                            buy_fee=buy_fee,
                            buy_timestamp=now_ms,
                        )
                    )

                    mode_prefix = "🟡 [SIM] " if dry_run else "🟢 "
                    coin = symbol.split("/")[0] if "/" in symbol else "BTC"
                    tp_pct = ((target_sell / exec_price) - 1.0) * 100.0 if exec_price > 0 else 0.0
                    await send_discord_bot_embed(
                        conn,
                        event_kind="BUY",
                        title=f"{mode_prefix}BUY T{sig.tranche_index} • {symbol} @ ${exec_price:,.2f}",
                        color=0x2ECC71 if dry_run else 0x00E676,
                        fields=[
                            {"name": "Volumen", "value": f"`{amount:.6f} {coin}` (${cost:,.2f})", "inline": True},
                            {"name": "Objetivo TP", "value": f"`${target_sell:,.2f}` (+{tp_pct:.2f}%)", "inline": True},
                            {"name": "Señal / Régimen", "value": f"`{sig.reason}`", "inline": False},
                        ],
                        footer_text=f"{bot_id} • {'Simulación Paper' if dry_run else 'Maker Limit'}",
                    )
                    mode_tag = "SIMULACIÓN" if dry_run else "EN VIVO"
                    print(
                        f"[BotSupervisor] 🟢 {bot_id} ({mode_tag}) BUY T{sig.tranche_index} @ ${exec_price:.2f} (${cost:.2f} USDT) -> TP ${target_sell:.2f}"
                    )

        return len(running_rows)


async def update_supervisor_heartbeat(pool, details: dict):
    """Actualiza el latido de vida del bot_supervisor en la tabla system_heartbeat."""
    try:
        async with pool.acquire() as conn:
            await conn.execute("""
                INSERT INTO system_heartbeat (service_name, last_heartbeat, status, details)
                VALUES ('bot_supervisor', NOW(), 'running', $1::jsonb)
                ON CONFLICT (service_name)
                DO UPDATE SET last_heartbeat = NOW(), status = 'running', details = EXCLUDED.details;
            """, json.dumps(details))
    except Exception as e:
        print(f"[BotSupervisor Heartbeat Warn] {e}")


async def run_bot_supervisor():
    """Demonio independiente 24/7 para la supervisión y ejecución de bots cuantitativos."""
    print("Iniciando CryptoView Bot Supervisor Autónomo 24/7...")
    pool = await init_db_pool()

    try:
        while True:
            start_ts = time.time()
            evaluated_count = 0
            try:
                evaluated_count = await evaluate_running_bots(pool)
            except Exception as e:
                print(f"[BotSupervisor Error] Excepción en ciclo de evaluación: {e}")

            duration_ms = int((time.time() - start_ts) * 1000)

            await update_supervisor_heartbeat(pool, {
                "running_bots_evaluated": evaluated_count,
                "cycle_duration_ms": duration_ms,
                "timestamp_utc": datetime.now(timezone.utc).isoformat()
            })

            sleep_sec = max(5, settings.BOT_SUPERVISOR_INTERVAL_SECONDS)
            await asyncio.sleep(sleep_sec)
    except (KeyboardInterrupt, asyncio.CancelledError):
        print("Deteniendo Bot Supervisor...")
    finally:
        await close_db_pool()


if __name__ == "__main__":
    asyncio.run(run_bot_supervisor())

