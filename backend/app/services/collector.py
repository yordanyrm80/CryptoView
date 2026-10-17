import asyncio
from datetime import datetime, timezone
from app.config import settings
from app.database import init_db_pool, close_db_pool
from app.services.exchange_client import ExchangeClient
from app.services.crypto import decrypt_secret

async def get_active_tracked_symbols(pool):
    """Obtiene la lista viva de monedas y su estado de backfill directamente de la base de datos."""
    async with pool.acquire() as conn:
        rows = await conn.fetch("""
            SELECT exchange, symbol, COALESCE(backfill_completed, FALSE) AS backfill_completed
            FROM tracked_symbols
            WHERE is_active = TRUE
            ORDER BY created_at ASC;
        """)
        return [(r['exchange'], r['symbol'], r['backfill_completed']) for r in rows]

async def mark_backfill_completed(pool, exchange: str, symbol: str):
    """Marca automáticamente en la BD que una moneda ya alcanzó el inicio de su historia en el exchange."""
    async with pool.acquire() as conn:
        await conn.execute("""
            UPDATE tracked_symbols
            SET backfill_completed = TRUE
            WHERE exchange = $1 AND symbol = $2;
        """, exchange, symbol)

async def sync_exchange_keys(pool, client: ExchangeClient):
    """Carga y descifra las credenciales de API de los exchanges guardadas en la base de datos."""
    try:
        async with pool.acquire() as conn:
            rows = await conn.fetch("""
                SELECT exchange, api_key_encrypted, api_secret_encrypted, api_passphrase_encrypted
                FROM api_keys
                WHERE is_active = TRUE;
            """)
        for r in rows:
            api_key = decrypt_secret(r['api_key_encrypted'])
            api_secret = decrypt_secret(r['api_secret_encrypted'])
            api_pass = decrypt_secret(r['api_passphrase_encrypted']) if r['api_passphrase_encrypted'] else ""
            if api_key and api_secret:
                await client.update_credentials(
                    exchange_name=r['exchange'],
                    api_key=api_key,
                    api_secret=api_secret,
                    api_passphrase=api_pass
                )
    except Exception as e:
        print(f"[Collector Keys Sync Error] No se pudieron sincronizar claves de BD: {e}")

async def get_latest_candle_time(pool, exchange: str, symbol: str):
    """Obtiene la marca de tiempo de la última vela (más reciente) guardada para este par."""
    async with pool.acquire() as conn:
        row = await conn.fetchrow("""
            SELECT MAX(time) as latest_time
            FROM market_candles
            WHERE exchange = $1 AND symbol = $2
        """, exchange, symbol)
        return row['latest_time'] if row else None

async def get_oldest_candle_time(pool, exchange: str, symbol: str):
    """Obtiene la marca de tiempo de la primera vela (más antigua) guardada para este par."""
    async with pool.acquire() as conn:
        row = await conn.fetchrow("""
            SELECT MIN(time) as oldest_time
            FROM market_candles
            WHERE exchange = $1 AND symbol = $2
        """, exchange, symbol)
        return row['oldest_time'] if row else None

async def save_candles(pool, exchange: str, symbol: str, candles: list):
    """Inserta o actualiza velas base de 1 minuto en la Hypertable de TimescaleDB."""
    if not candles:
        return 0

    query = """
        INSERT INTO market_candles (time, exchange, symbol, open, high, low, close, volume)
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
        ON CONFLICT (time, exchange, symbol)
        DO UPDATE SET
            high = GREATEST(market_candles.high, EXCLUDED.high),
            low = LEAST(market_candles.low, EXCLUDED.low),
            close = EXCLUDED.close,
            volume = EXCLUDED.volume;
    """

    records = [
        (c['time'], exchange, symbol, c['open'], c['high'], c['low'], c['close'], c['volume'])
        for c in candles
    ]

    async with pool.acquire() as conn:
        await conn.executemany(query, records)

    return len(records)

async def sync_symbol_forward(client: ExchangeClient, pool, exchange: str, symbol: str):
    """Tarea 1 (Tiempo Real): Descarga las velas recientes de 1 minuto ('1m') hasta el presente."""
    latest_time = await get_latest_candle_time(pool, exchange, symbol)
    
    since_ms = None
    if latest_time:
        # Retroceder 2 minutos para actualizar la vela viva en curso
        since_ms = int((latest_time.timestamp() - 120) * 1000)

    candles = await client.fetch_ohlcv(exchange, symbol, timeframe='1m', since=since_ms, limit=1000)
    
    if candles:
        saved_count = await save_candles(pool, exchange, symbol, candles)
        now_utc = datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M:%S UTC')
        print(f"[{now_utc}] ⚡ LIVE {exchange.upper()} {symbol} (1m): {saved_count} velas actualizadas.")

async def refresh_aggregates_window(pool, start_dt: datetime, end_dt: datetime):
    """Refresca las vistas materializadas continuas (5m, 1h, 1d) para el rango histórico recién descargado."""
    try:
        async with pool.acquire() as conn:
            for view_name in ('candles_1d', 'candles_1h', 'candles_5m'):
                await conn.execute(
                    f"CALL refresh_continuous_aggregate('{view_name}', $1::timestamptz, $2::timestamptz);",
                    start_dt,
                    end_dt,
                )
    except Exception as e:
        print(f"[Warn Aggregate Refresh] {e}")

async def sync_symbol_backward(client: ExchangeClient, pool, exchange: str, symbol: str):
    """Tarea 2 (Backfill Progresivo): Retrocede un bloque de 25 horas (1500 velas de 1m) hacia el pasado."""
    oldest_time = await get_oldest_candle_time(pool, exchange, symbol)
    if not oldest_time:
        return

    before_sec = int(oldest_time.timestamp())
    candles, reached_genesis = await client.fetch_ohlcv_backfill(
        exchange_name=exchange,
        symbol=symbol,
        before_timestamp_sec=before_sec,
        limit=1500
    )

    now_utc = datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M:%S UTC')

    if reached_genesis:
        await mark_backfill_completed(pool, exchange, symbol)
        oldest_str = oldest_time.strftime('%Y-%m-%d %H:%M UTC')
        print(f"[{now_utc}] ✅ BACKFILL COMPLETADO: {exchange.upper()} {symbol} alcanzó su origen histórico ({oldest_str}).")
        return

    if candles:
        saved_count = await save_candles(pool, exchange, symbol, candles)
        # Refrescar vistas continuas (1d, 1h, 5m) en segundo plano sin bloquear el bucle de ingesta
        from datetime import timedelta
        win_start = candles[0]['time'] - timedelta(days=1)
        win_end = candles[-1]['time'] + timedelta(days=1)
        asyncio.create_task(refresh_aggregates_window(pool, win_start, win_end))
        new_oldest = candles[0]['time'].strftime('%Y-%m-%d %H:%M UTC')
        print(f"[{now_utc}] ⏪ BACKFILL {exchange.upper()} {symbol}: +{saved_count} velas antiguas guardadas (Historial ya llega hasta {new_oldest}).")

import json
import time

async def update_worker_heartbeat(pool, details: dict):
    """Actualiza la marca de latido del worker en system_heartbeat para monitoreo en vivo."""
    try:
        async with pool.acquire() as conn:
            await conn.execute("""
                INSERT INTO system_heartbeat (service_name, last_heartbeat, status, details)
                VALUES ('collector', NOW(), 'running', $1::jsonb)
                ON CONFLICT (service_name)
                DO UPDATE SET last_heartbeat = NOW(), status = 'running', details = EXCLUDED.details;
            """, json.dumps(details))
    except Exception as e:
        print(f"[Heartbeat Warn] {e}")

async def auto_sync_exchange_trades(pool, client: ExchangeClient):
    """Sincroniza en segundo plano las últimas órdenes ejecutadas (48h) de los exchanges configurados."""
    try:
        async with pool.acquire() as conn:
            active_keys = await conn.fetch("SELECT exchange FROM api_keys WHERE is_active = TRUE;")
        for k in active_keys:
            ex_name = k["exchange"].lower().strip()
            ex_instance = await client.get_exchange(ex_name)
            if not ex_instance:
                continue
            since_ms = int((datetime.now(timezone.utc) - timedelta(days=2)).timestamp() * 1000)
            try:
                trades = await ex_instance.fetch_my_trades(symbol=None, since=since_ms, limit=100)
                if trades:
                    insert_query = """
                        INSERT INTO account_trades (trade_id, order_id, exchange, symbol, side, price, amount, fee, fee_currency, time, remaining_amount, notes)
                        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12)
                        ON CONFLICT (exchange, trade_id) DO NOTHING;
                    """
                    async with pool.acquire() as conn:
                        async with conn.transaction():
                            for t in trades:
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
                                await conn.execute(
                                    insert_query,
                                    t_id, str(t.get('order') or ''), ex_name, t_sym, t_side,
                                    t_price, t_amount, t_fee, t_fee_curr, t_time,
                                    t_amount if t_side == 'buy' else 0.0,
                                    f"Auto-Sync 24/7 ({ex_name.upper()})"
                                )
                    now_str = datetime.now(timezone.utc).strftime('%H:%M:%S UTC')
                    print(f"[{now_str}] 🔄 Auto-Sync Trades {ex_name.upper()}: {len(trades)} órdenes procesadas en segundo plano.")
            except Exception:
                pass
    except Exception as e:
        print(f"[AutoSyncTrades Error] {e}")

async def run_collector():
    print("Iniciando CryptoView Ingestion Worker 24/7 (Tiempo Real + Backfill + Auto-Sync Trades)...")
    pool = await init_db_pool()
    client = ExchangeClient()

    backfill_cursor = 0
    last_trades_sync = 0.0

    try:
        while True:
            # 1. Cargar y actualizar claves cifradas de exchanges desde la base de datos
            await sync_exchange_keys(pool, client)

            # 2. Leer dinámicamente qué monedas están activas en PostgreSQL
            active_symbols = await get_active_tracked_symbols(pool)

            # 3. Tarea Periódica: Auto-Sync de Trades cada 10 minutos (600s)
            now_epoch = time.time()
            if now_epoch - last_trades_sync >= 600:
                await auto_sync_exchange_trades(pool, client)
                last_trades_sync = now_epoch

            if not active_symbols:
                now_utc = datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M:%S UTC')
                print(f"[{now_utc}] Sin monedas activas en tracked_symbols. Esperando...")
                await update_worker_heartbeat(pool, {"status": "waiting_symbols", "active_symbols": 0})
                await asyncio.sleep(10)
                continue

            # 4. Tarea 1: Sincronizar Tiempo Real (hacia adelante) para todas las monedas activas
            for exchange, symbol, _ in active_symbols:
                try:
                    await sync_symbol_forward(client, pool, exchange, symbol)
                    await asyncio.sleep(1.5)  # Pausa gentil entre peticiones
                except Exception as e:
                    print(f"[Error Collector Forward] {exchange} {symbol}: {e}")

            # 5. Tarea 2: Backfill Progresivo (hacia atrás) con Round-Robin rotativo
            pending_backfill = [(ex, sym) for ex, sym, done in active_symbols if not done]
            if pending_backfill:
                backfill_cursor = backfill_cursor % len(pending_backfill)
                ex_bf, sym_bf = pending_backfill[backfill_cursor]
                backfill_cursor = (backfill_cursor + 1) % len(pending_backfill)
                try:
                    await asyncio.sleep(2.5)  # Pausa extra antes del bloque histórico
                    await sync_symbol_backward(client, pool, ex_bf, sym_bf)
                except Exception as e:
                    print(f"[Error Collector Backfill] {ex_bf} {sym_bf}: {e}")

            # 6. Actualizar latido saludable (Heartbeat) del worker
            await update_worker_heartbeat(pool, {
                "active_symbols": len(active_symbols),
                "pending_backfill": len(pending_backfill),
                "timestamp_utc": datetime.now(timezone.utc).isoformat()
            })

            # Reposo entre ciclos (20s por defecto)
            await asyncio.sleep(settings.COLLECTOR_SLEEP_SECONDS)
    except (KeyboardInterrupt, asyncio.CancelledError):
        print("Deteniendo Ingestion Worker...")
    finally:
        await client.close()
        await close_db_pool()

if __name__ == "__main__":
    asyncio.run(run_collector())
