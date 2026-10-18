import logging
import time
from typing import Any, Dict, List, Optional
import ccxt
from src.domain.models import Candle

logger = logging.getLogger(__name__)


class KuCoinClient:
    """Client for KuCoin API via CCXT with exponential backoff, rate limiting, and precision formatting."""

    def __init__(self, api_key: Optional[str] = None, secret: Optional[str] = None, passphrase: Optional[str] = None):
        config = {
            "enableRateLimit": True,
            "timeout": 30000,
            "options": {
                "defaultType": "spot",
                "adjustForTimeDifference": True,
            },
        }
        if api_key and secret and passphrase:
            config.update({
                "apiKey": api_key,
                "secret": secret,
                "password": passphrase,
            })

        self.api_key = api_key
        self.exchange = ccxt.kucoin(config)
        self._markets_loaded = False
        self._try_load_markets()

    def _try_load_markets(self) -> None:
        """Safely loads exchange markets and precision rules."""
        try:
            self.exchange.load_markets()
            self._markets_loaded = True
            logger.info("KuCoin markets metadata and precision tables loaded successfully.")
        except Exception as e:
            logger.warning(f"Could not load KuCoin markets immediately (will retry on demand): {e}")

    def fetch_ohlcv(
        self,
        symbol: str,
        timeframe: str = "1h",
        since: Optional[int] = None,
        limit: int = 500,
        max_retries: int = 5,
    ) -> List[Candle]:
        """Fetches a batch of OHLCV candles from KuCoin with exponential backoff."""
        retries = 0
        backoff = 1.0

        while retries < max_retries:
            try:
                raw_candles = self.exchange.fetch_ohlcv(
                    symbol=symbol,
                    timeframe=timeframe,
                    since=since,
                    limit=limit,
                )

                candles = [
                    Candle(
                        symbol=symbol,
                        timeframe=timeframe,
                        timestamp=int(c[0]),
                        open=float(c[1]),
                        high=float(c[2]),
                        low=float(c[3]),
                        close=float(c[4]),
                        volume=float(c[5]),
                    )
                    for c in raw_candles
                ]
                return candles

            except (ccxt.NetworkError, ccxt.RateLimitExceeded) as e:
                retries += 1
                logger.warning(
                    f"Network/rate limit error for {symbol} ({e}). Retry {retries}/{max_retries} in {backoff:.1f}s..."
                )
                time.sleep(backoff)
                backoff *= 2.0
            except Exception as e:
                logger.error(f"Unexpected error fetching candles for {symbol}: {e}")
                raise e

        raise RuntimeError(f"Exceeded maximum retries for {symbol}.")

    def fetch_balance(self, max_retries: int = 3) -> Dict[str, Any]:
        """Fetches account/subaccount balance from KuCoin."""
        retries = 0
        backoff = 1.0
        while retries < max_retries:
            try:
                return self.exchange.fetch_balance()
            except (ccxt.NetworkError, ccxt.RateLimitExceeded) as e:
                retries += 1
                logger.warning(f"Error fetching balance ({e}). Retry {retries}/{max_retries}...")
                time.sleep(backoff)
                backoff *= 2.0
            except Exception as e:
                logger.error(f"Unexpected error fetching balance: {e}")
                raise e
        raise RuntimeError("Failed to fetch balance from KuCoin after retries.")

    def fetch_free_balance(self, currency: str = "USDT") -> float:
        """Fetches available free balance for a specific currency."""
        balance = self.fetch_balance()
        free_dict = balance.get("free", {})
        return float(free_dict.get(currency, 0.0))

    def create_order(
        self,
        symbol: str,
        side: str,
        order_type: str,
        amount: float,
        price: Optional[float] = None,
        max_retries: int = 3,
    ) -> Dict[str, Any]:
        """Places a resting spot order on KuCoin with strict precision formatting. Never touches withdrawal APIs."""
        if not self._markets_loaded:
            self._try_load_markets()

        retries = 0
        backoff = 1.0
        clean_side = side.lower()
        clean_type = order_type.lower()

        # Format amount and price to KuCoin exact lot/price precision
        formatted_amount = amount
        formatted_price = price
        if self._markets_loaded:
            try:
                formatted_amount = float(self.exchange.amount_to_precision(symbol, amount))
                if price is not None:
                    formatted_price = float(self.exchange.price_to_precision(symbol, price))
            except Exception as e:
                logger.warning(f"Could not apply precision formatting for {symbol}: {e}")

        while retries < max_retries:
            try:
                logger.info(
                    f"Submitting {clean_type.upper()} {clean_side.upper()} order: {formatted_amount} {symbol} @ {formatted_price} (Maker)..."
                )
                order = self.exchange.create_order(
                    symbol=symbol,
                    type=clean_type,
                    side=clean_side,
                    amount=formatted_amount,
                    price=formatted_price,
                )
                logger.info(
                    f"Order resting on KuCoin: ID={order.get('id')}, status={order.get('status')}"
                )
                return order
            except (ccxt.NetworkError, ccxt.RateLimitExceeded) as e:
                retries += 1
                logger.warning(f"Network/rate limit error placing order ({e}). Retry {retries}/{max_retries}...")
                time.sleep(backoff)
                backoff *= 2.0
            except Exception as e:
                logger.error(f"Fatal exchange error placing order on KuCoin: {e}", exc_info=True)
                raise e
        raise RuntimeError(f"Failed to place {clean_side} order on KuCoin after {max_retries} retries.")

    def cancel_order(self, order_id: str, symbol: str) -> Dict[str, Any]:
        """Cancels an active order on KuCoin."""
        try:
            return self.exchange.cancel_order(id=order_id, symbol=symbol)
        except Exception as e:
            logger.error(f"Error cancelling order {order_id} on KuCoin: {e}")
            raise e

    def fetch_order(self, order_id: str, symbol: str) -> Dict[str, Any]:
        """Fetches status and details of an order on KuCoin."""
        try:
            return self.exchange.fetch_order(id=order_id, symbol=symbol)
        except Exception as e:
            logger.error(f"Error fetching order {order_id} from KuCoin: {e}")
            raise e

    def fetch_open_orders(self, symbol: Optional[str] = None) -> List[Dict[str, Any]]:
        """Fetches all resting open orders on KuCoin."""
        try:
            return self.exchange.fetch_open_orders(symbol=symbol)
        except Exception as e:
            logger.error(f"Error fetching open orders from KuCoin: {e}")
            return []

    def close(self):
        """Closes exchange resources if applicable."""
        pass
