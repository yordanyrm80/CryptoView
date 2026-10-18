import argparse
import logging
import sys
import time
from datetime import datetime, timezone, timedelta
from pathlib import Path

# Añadir el directorio raíz al path para ejecución directa
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from src.domain.models import Candle
from src.exchange.client import KuCoinClient
from src.exchange.cryptoview_client import CryptoViewClient
from src.storage.candle_repository import CandleRepository
from src.storage.database import DatabaseManager

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%H:%M:%S",
)
logger = logging.getLogger("Downloader")


def download_historical_candles(
    repo: CandleRepository,
    symbol: str,
    timeframe: str = "1h",
    days: int = 365,
    source: str = "cryptoview",
    exchange: str = "kucoin",
    kucoin_client: KuCoinClient = None,
    cryptoview_client: CryptoViewClient = None,
):
    """Descarga velas hacia adelante desde (ahora - días) hasta el presente con paginación limpia."""
    now_dt = datetime.now(timezone.utc)
    start_dt = now_dt - timedelta(days=days)
    since_ms = int(start_dt.timestamp() * 1000)
    now_ms = int(now_dt.timestamp() * 1000)

    # Verificar si ya tenemos velas previas en la base de datos
    earliest_saved = repo.get_earliest_timestamp(symbol, timeframe)
    latest_saved = repo.get_latest_timestamp(symbol, timeframe)

    # Si estamos descargando hacia el pasado, nos detenemos en cuanto empalmemos con earliest_saved
    if earliest_saved and since_ms < earliest_saved:
        target_end_ms = earliest_saved
        logger.info(
            f"[{symbol}] Llenando hueco histórico hacia el pasado: {start_dt:%Y-%m-%d} hasta {datetime.fromtimestamp(earliest_saved/1000, tz=timezone.utc):%Y-%m-%d}"
        )
    else:
        target_end_ms = now_ms
        logger.info(
            f"[{symbol}] Descargando datos históricos de {days} días ({start_dt:%Y-%m-%d} a {now_dt:%Y-%m-%d}) vía {source.upper()}"
        )

    total_downloaded = 0
    limit = 1500 if source == "cryptoview" else 500
    interval_ms = 3600 * 1000 if timeframe == "1h" else 60 * 1000

    while since_ms < target_end_ms:
        candles = []
        if source == "cryptoview" and cryptoview_client is not None:
            try:
                candles = cryptoview_client.fetch_candles_sync(
                    symbol=symbol,
                    timeframe=timeframe,
                    exchange=exchange,
                    limit=limit,
                    start_time_ms=since_ms,
                    end_time_ms=target_end_ms,
                    auto_track=True,
                )
            except Exception as e:
                logger.warning(f"CryptoView download error ({e}), intentando fallback con KuCoin CCXT...")
                if kucoin_client:
                    candles = kucoin_client.fetch_ohlcv(symbol=symbol, timeframe=timeframe, since=since_ms, limit=500)

        elif kucoin_client is not None:
            candles = kucoin_client.fetch_ohlcv(symbol=symbol, timeframe=timeframe, since=since_ms, limit=limit)

        if not candles:
            break

        saved_count = repo.save_candles(candles)
        total_downloaded += len(candles)

        last_ts = candles[-1].timestamp
        last_dt = datetime.fromtimestamp(last_ts / 1000.0, tz=timezone.utc)

        logger.info(
            f"[{symbol}] Descargadas {len(candles)} velas (última: {last_dt:%Y-%m-%d %H:%M}). Guardadas {saved_count} nuevas."
        )

        # Si el último timestamp no avanza, evitamos bucle infinito
        if last_ts <= since_ms:
            since_ms += interval_ms * len(candles)
        else:
            since_ms = last_ts + interval_ms

        time.sleep(0.05 if source == "cryptoview" else 0.3)

    total_in_db = repo.count_candles(symbol, timeframe)
    logger.info(f"[{symbol}] Descarga finalizada. Total de velas en PostgreSQL: {total_in_db}")


def main():
    parser = argparse.ArgumentParser(description="Descargador de datos históricos de velas a PostgreSQL")
    parser.add_argument(
        "--symbols",
        nargs="+",
        default=["BTC/USDT", "ETH/USDT", "LTC/USDT"],
        help="Pares a descargar",
    )
    parser.add_argument("--timeframe", default="1h", help="Temporalidad de velas (ej. 1h, 15m, 4h)")
    parser.add_argument("--days", type=int, default=365, help="Días de historial a descargar")
    parser.add_argument("--source", choices=["cryptoview", "kucoin"], default="cryptoview", help="Fuente de datos (cryptoview API o kucoin CCXT)")
    parser.add_argument("--exchange", default="kucoin", help="Nombre del exchange en CryptoView (kucoin, binance)")
    parser.add_argument("--db", default=None, help="URL de la base de datos PostgreSQL")

    args = parser.parse_args()

    db_manager = DatabaseManager(args.db)
    repo = CandleRepository(db_manager)
    kucoin_client = KuCoinClient()
    cryptoview_client = CryptoViewClient()

    logger.info(f"Iniciando descarga ({args.source.upper()}) para: {', '.join(args.symbols)} en temporalidad {args.timeframe}")

    for symbol in args.symbols:
        download_historical_candles(
            repo=repo,
            symbol=symbol,
            timeframe=args.timeframe,
            days=args.days,
            source=args.source,
            exchange=args.exchange,
            kucoin_client=kucoin_client,
            cryptoview_client=cryptoview_client,
        )

    logger.info("Todos los datos históricos fueron almacenados exitosamente en PostgreSQL.")


if __name__ == "__main__":
    main()
