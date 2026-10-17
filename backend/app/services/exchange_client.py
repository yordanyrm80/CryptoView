import asyncio
import ccxt.async_support as ccxt
import httpx
from typing import List, Dict, Any, Optional, Tuple
from datetime import datetime, timezone

class ExchangeClient:
    def __init__(self):
        self.exchanges: Dict[str, Any] = {}
        self._exchange_configs: Dict[str, Dict[str, Any]] = {}
        self._http_client = httpx.AsyncClient(timeout=20.0)

    async def get_exchange(self, exchange_name: str) -> Optional[Any]:
        ex_name = exchange_name.lower().strip()
        if ex_name in self.exchanges:
            return self.exchanges[ex_name]

        if not hasattr(ccxt, ex_name):
            print(f"[ExchangeClient] Exchange no soportado por CCXT: {ex_name}")
            return None

        cfg = self._exchange_configs.get(ex_name, {
            'enableRateLimit': True,
        })
        exchange_class = getattr(ccxt, ex_name)
        instance = exchange_class(cfg)
        self.exchanges[ex_name] = instance
        return instance

    async def update_credentials(self, exchange_name: str, api_key: str = "", api_secret: str = "", api_passphrase: str = ""):
        ex_name = exchange_name.lower().strip()
        cfg: Dict[str, Any] = {
            'enableRateLimit': True,
        }
        if api_key and api_secret:
            cfg['apiKey'] = api_key
            cfg['secret'] = api_secret
            if api_passphrase:
                cfg['password'] = api_passphrase

        if ex_name in self.exchanges:
            try:
                await self.exchanges[ex_name].close()
            except Exception:
                pass
            del self.exchanges[ex_name]

        self._exchange_configs[ex_name] = cfg

    async def fetch_ohlcv(self, exchange_name: str, symbol: str, timeframe: str = '1m',
                          since: Optional[int] = None, limit: int = 1000) -> List[Dict[str, Any]]:
        ex_name = exchange_name.lower().strip()
        norm_symbol = symbol.replace('-', '/').upper()

        if ex_name == 'binance':
            try:
                binance_sym = norm_symbol.replace('/', '')
                params: Dict[str, Any] = {
                    'symbol': binance_sym,
                    'interval': timeframe,
                    'limit': limit,
                }
                if since is not None:
                    params['startTime'] = since

                resp = await self._http_client.get(
                    'https://data-api.binance.vision/api/v3/klines',
                    params=params,
                )
                if resp.status_code == 429:
                    print("[RateLimit] Binance 429 detectado. Pausando 30s...")
                    await asyncio.sleep(30)
                    return []
                resp.raise_for_status()
                raw_candles = resp.json()
                return [
                    {
                        'time': datetime.fromtimestamp(c[0] / 1000.0, tz=timezone.utc),
                        'open': float(c[1]),
                        'high': float(c[2]),
                        'low': float(c[3]),
                        'close': float(c[4]),
                        'volume': float(c[5]) if len(c) > 5 else 0.0,
                    }
                    for c in raw_candles
                ]
            except Exception as e:
                print(f"[ExchangeClient Error] binance {symbol} {timeframe}: {e}")
                return []

        ex = await self.get_exchange(ex_name)
        if not ex:
            return []

        try:
            raw_candles = await ex.fetch_ohlcv(norm_symbol, timeframe=timeframe, since=since, limit=limit)
            result = []
            for c in raw_candles:
                result.append({
                    'time': datetime.fromtimestamp(c[0] / 1000.0, tz=timezone.utc),
                    'open': float(c[1]),
                    'high': float(c[2]),
                    'low': float(c[3]),
                    'close': float(c[4]),
                    'volume': float(c[5]) if len(c) > 5 else 0.0,
                })
            return result
        except ccxt.RateLimitExceeded as e:
            print(f"[RateLimit] Límite alcanzado en {exchange_name} ({e}). Pausando 45s por seguridad...")
            await asyncio.sleep(45)
            return []
        except Exception as e:
            print(f"[ExchangeClient Error] {exchange_name} {symbol} {timeframe}: {e}")
            return []

    async def fetch_ohlcv_backfill(
        self,
        exchange_name: str,
        symbol: str,
        before_timestamp_sec: int,
        limit: int = 1500
    ) -> Tuple[List[Dict[str, Any]], bool]:
        """
        Descarga un bloque histórico de velas de 1m anteriores a `before_timestamp_sec`.
        Retorna: (lista_de_velas, llego_al_origen_historico)
        - Si ocurre un error de red o rate limit, retorna ([], False) para reintentar en el siguiente ciclo.
        - Solo retorna ([], True) cuando el exchange confirma con HTTP 200 que ya no existen velas más antiguas.
        """
        ex_name = exchange_name.lower().strip()
        norm_symbol = symbol.replace('-', '/').upper()

        if ex_name == 'kucoin':
            kucoin_sym = norm_symbol.replace('/', '-')
            end_at = before_timestamp_sec
            start_at = end_at - (limit * 60)

            try:
                resp = await self._http_client.get(
                    'https://api.kucoin.com/api/v1/market/candles',
                    params={
                        'type': '1min',
                        'symbol': kucoin_sym,
                        'startAt': start_at,
                        'endAt': end_at,
                    }
                )
                if resp.status_code == 429:
                    print("[RateLimit KuCoin] HTTP 429 en backfill. Pausando 60s...")
                    await asyncio.sleep(60)
                    return [], False

                resp.raise_for_status()
                payload = resp.json()

                if payload.get('code') == '429000':
                    print("[RateLimit KuCoin] Código 429000 en backfill. Pausando 60s...")
                    await asyncio.sleep(60)
                    return [], False

                if payload.get('code') != '200000':
                    print(f"[KuCoin Backfill Warning] Respuesta inesperada: {payload}")
                    return [], False

                raw_list = payload.get('data') or []

                # Si el bloque de 25 horas vino vacío, verificamos con una consulta abierta (sin startAt)
                # para distinguir entre un mantenimiento temporal del exchange y el origen real de la moneda.
                if not raw_list:
                    await asyncio.sleep(2.5)
                    check_resp = await self._http_client.get(
                        'https://api.kucoin.com/api/v1/market/candles',
                        params={
                            'type': '1min',
                            'symbol': kucoin_sym,
                            'endAt': end_at - 60,
                        }
                    )
                    if check_resp.status_code == 429:
                        await asyncio.sleep(60)
                        return [], False
                    check_resp.raise_for_status()
                    check_payload = check_resp.json()
                    if check_payload.get('code') != '200000':
                        return [], False

                    raw_list = check_payload.get('data') or []
                    if not raw_list:
                        # Confirmado con 200 OK: no existe ninguna vela anterior en KuCoin
                        return [], True

                # KuCoin devuelve: [time_sec_str, open, close, high, low, volume, turnover]
                candles = []
                for c in raw_list:
                    ts_sec = int(c[0])
                    if ts_sec < before_timestamp_sec:
                        candles.append({
                            'time': datetime.fromtimestamp(ts_sec, tz=timezone.utc),
                            'open': float(c[1]),
                            'close': float(c[2]),
                            'high': float(c[3]),
                            'low': float(c[4]),
                            'volume': float(c[5]) if len(c) > 5 else 0.0,
                        })
                candles.sort(key=lambda x: x['time'])
                return candles, False

            except Exception as e:
                print(f"[KuCoin Backfill Error] {symbol}: {e}")
                return [], False

        # Fallback genérico para otros exchanges
        since_ms = (before_timestamp_sec - (limit * 60)) * 1000
        candles = await self.fetch_ohlcv(ex_name, norm_symbol, timeframe='1m', since=since_ms, limit=limit)
        filtered = [c for c in candles if int(c['time'].timestamp()) < before_timestamp_sec]
        return filtered, False

    async def close(self):
        try:
            await self._http_client.aclose()
        except Exception:
            pass
        for ex in list(self.exchanges.values()):
            try:
                await ex.close()
            except Exception:
                pass
        self.exchanges.clear()
