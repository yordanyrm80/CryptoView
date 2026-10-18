import sys
import time
from datetime import datetime, timezone
from pathlib import Path

# Agregar raíz del proyecto
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from src.exchange.client import KuCoinClient
from src.storage.candle_repository import CandleRepository
from src.storage.database import DatabaseManager


def backfill_symbol(client: KuCoinClient, repo: CandleRepository, symbol: str, start_dt_str: str):
    start_ts = int(datetime.fromisoformat(start_dt_str).replace(tzinfo=timezone.utc).timestamp() * 1000)
    earliest_in_db = repo.get_earliest_timestamp(symbol, "1h")

    if not earliest_in_db:
        print(f"[{symbol}] No hay velas en la base de datos para determinar el punto de corte.")
        return

    earliest_dt = datetime.fromtimestamp(earliest_in_db / 1000, tz=timezone.utc)
    print(f"\n=======================================================")
    print(f"[{symbol}] Iniciando backfill desde {start_dt_str} hasta {earliest_dt:%Y-%m-%d %H:%M}")
    print(f"=======================================================")

    since_ms = start_ts
    total_saved = 0

    while since_ms < earliest_in_db:
        candles = client.fetch_ohlcv(symbol, "1h", since=since_ms, limit=500)
        if not candles:
            print(f"[{symbol}] Sin velas en {datetime.fromtimestamp(since_ms/1000, tz=timezone.utc)}, avanzando 2 días...")
            since_ms += 2 * 86400 * 1000
            time.sleep(0.3)
            continue

        saved = repo.save_candles(candles)
        total_saved += saved
        last_ts = candles[-1].timestamp
        last_dt = datetime.fromtimestamp(last_ts / 1000, tz=timezone.utc)
        print(f"[{symbol}] Descargadas {len(candles)} velas (hasta {last_dt:%Y-%m-%d %H:%M}) | Guardadas: {saved}")

        since_ms = last_ts + 3600 * 1000
        time.sleep(0.3)

        if since_ms >= earliest_in_db:
            break

    total_in_db = repo.count_candles(symbol, "1h")
    print(f"[{symbol}] Backfill completado exitosamente.")
    print(f"[{symbol}] Nuevas velas guardadas: {total_saved} | Total ahora en DB: {total_in_db}\n")


def main():
    db = DatabaseManager()
    repo = CandleRepository(db)
    client = KuCoinClient()

    # 1. Backfill ETH/USDT desde el 1 de noviembre de 2017
    backfill_symbol(client, repo, "ETH/USDT", "2017-11-01")

    # 2. Backfill LTC/USDT desde el 25 de enero de 2018
    backfill_symbol(client, repo, "LTC/USDT", "2018-01-25")

    print("\n[✓] TODOS LOS ACTIVOS (BTC, ETH, LTC) TIENEN SU HISTORIAL COMPLETO EN POSTGRESQL.")


if __name__ == "__main__":
    main()
