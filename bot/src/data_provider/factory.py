import logging
import os
from typing import Optional
from src.data_provider.api_provider import ApiMarketDataProvider
from src.data_provider.base import MarketDataProvider
from src.data_provider.timescale_provider import TimescaleMarketDataProvider

logger = logging.getLogger("criptobot.data_provider.factory")

_singleton_provider: Optional[MarketDataProvider] = None


def get_market_data_provider(
    mode: Optional[str] = None,
    force_new: bool = False,
) -> MarketDataProvider:
    """Factory to instantiate the configured MarketDataProvider.
    
    Reads DATA_SOURCE_MODE strictly from the environment/.env:
    - 'database': Direct SQL access to PostgreSQL / TimescaleDB (local deployment).
    - 'api': Remote HTTPS REST API calls to CryptoView (remote/cloud deployment).
    
    Strict rule: No automatic guessing or fallback; mode is explicitly set in .env.
    """
    global _singleton_provider

    if _singleton_provider is not None and not force_new:
        return _singleton_provider

    selected_mode = (mode or os.getenv("DATA_SOURCE_MODE", "api")).lower().strip()

    if selected_mode == "database":
        logger.info("[DataProvider] Activating TimescaleMarketDataProvider (Mode: database / Direct SQL)")
        provider = TimescaleMarketDataProvider()
    elif selected_mode == "api":
        logger.info("[DataProvider] Activating ApiMarketDataProvider (Mode: api / REST API)")
        provider = ApiMarketDataProvider()
    else:
        raise ValueError(
            f"Invalid DATA_SOURCE_MODE='{selected_mode}' configured in .env. "
            f"Must be explicitly set to either 'database' (same server) or 'api' (remote server)."
        )

    if not force_new:
        _singleton_provider = provider

    return provider
