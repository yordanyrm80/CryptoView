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
        new_oldest = candles[0]['time'].strftime('%Y-%m-%d %H:%M UTC')
        print(f"[{now_utc}] ⏪ BACKFILL {exchange.upper()} {symbol}: +{saved_count} velas antiguas guardadas (Historial ya llega hasta {new_oldest}).")

async def run_collector():
    print("Iniciando CryptoView Ingestion Worker 24/7 (Tiempo Real + Backfill Progresivo Seguro)...")
    pool = await init_db_pool()
    client = ExchangeClient()

    try:
        while True:
            # 1. Cargar y actualizar claves cifradas de exchanges desde la base de datos
            await sync_exchange_keys(pool, client)

            # 2. Leer dinámicamente qué monedas están activas en PostgreSQL
            active_symbols = await get_active_tracked_symbols(pool)

            if not active_symbols:
                now_utc = datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M:%S UTC')
                print(f"[{now_utc}] Sin monedas activas en tracked_symbols. Esperando...")
                await asyncio.sleep(10)
                continue

            # 3. Tarea 1: Sincronizar Tiempo Real (hacia adelante) para todas las monedas activas
            for exchange, symbol, _ in active_symbols:
                try:
                    await sync_symbol_forward(client, pool, exchange, symbol)
                    await asyncio.sleep(1.5)  # Pausa gentil entre peticiones
                except Exception as e:
                    print(f"[Error Collector Forward] {exchange} {symbol}: {e}")

            # 4. Tarea 2: Backfill Progresivo (hacia atrás) — Máximo 1 petición por ciclo de 20s
            # para respetar al máximo los límites de tasa de KuCoin.
            pending_backfill = [(ex, sym) for ex, sym, done in active_symbols if not done]
            if pending_backfill:
                ex_bf, sym_bf = pending_backfill[0]
                try:
                    await asyncio.sleep(2.5)  # Pausa extra antes del bloque histórico
                    await sync_symbol_backward(client, pool, ex_bf, sym_bf)
                except Exception as e:
                    print(f"[Error Collector Backfill] {ex_bf} {sym_bf}: {e}")

            # Reposo entre ciclos (20s por defecto)
            await asyncio.sleep(settings.COLLECTOR_SLEEP_SECONDS)
    except (KeyboardInterrupt, asyncio.CancelledError):
        print("Deteniendo Ingestion Worker...")
    finally:
        await client.close()
        await close_db_pool()

if __name__ == "__main__":
    asyncio.run(run_collector())
