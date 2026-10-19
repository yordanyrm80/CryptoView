import asyncio
import pytest
from unittest.mock import AsyncMock, MagicMock
from src.data_provider import (
    MarketDataProvider,
    TimescaleMarketDataProvider,
    ApiMarketDataProvider,
    get_market_data_provider,
)
from src.domain.models import Candle
from src.core.ingestor import MarketDataIngestor
from src.core.event_bus import EventBus


def test_factory_creates_api_provider():
    provider = get_market_data_provider(mode="api", force_new=True)
    assert isinstance(provider, ApiMarketDataProvider)
    assert provider.base_url.startswith("http")


def test_factory_creates_database_provider():
    provider = get_market_data_provider(mode="database", force_new=True)
    assert isinstance(provider, TimescaleMarketDataProvider)
    assert "postgresql://" in provider.connection_url or "postgres://" in provider.connection_url


def test_factory_rejects_invalid_mode():
    with pytest.raises(ValueError, match="Invalid DATA_SOURCE_MODE"):
        get_market_data_provider(mode="invalid_mode", force_new=True)


@pytest.mark.anyio
async def test_market_data_ingestor_uses_provider_without_ccxt():
    mock_provider = MagicMock(spec=MarketDataProvider)
    sample_candles = [
        Candle(
            symbol="BTC/USDT",
            timeframe="1h",
            timestamp=1700000000000,
            open=65000.0,
            high=65500.0,
            low=64800.0,
            close=65200.0,
            volume=120.5,
        )
    ]
    mock_provider.get_candles = AsyncMock(return_value=sample_candles)

    mock_db = MagicMock()
    mock_repo = MagicMock()
    mock_repo.save_candles.return_value = 1
    event_bus = EventBus()

    received_events = []

    async def _on_event(e):
        received_events.append(e)

    event_bus.subscribe("CANDLE_INGESTED", _on_event)

    ingestor = MarketDataIngestor(
        db_manager=mock_db,
        candle_repo=mock_repo,
        data_provider=mock_provider,
        event_bus=event_bus,
        symbols=["BTC/USDT"],
    )

    saved_count = await ingestor.sync_once()
    await asyncio.sleep(0.05)

    assert saved_count == 1
    mock_provider.get_candles.assert_awaited_once_with(
        symbol="BTC/USDT",
        timeframe="1h",
        exchange="kucoin",
        limit=5,
    )
    mock_repo.save_candles.assert_called_once_with(sample_candles)
    assert len(received_events) == 1
    assert received_events[0].data["close"] == 65200.0
