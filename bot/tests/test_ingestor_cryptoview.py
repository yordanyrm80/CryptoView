import pytest
from unittest.mock import AsyncMock, MagicMock
from src.core.ingestor import MarketDataIngestor
from src.domain.models import Candle


@pytest.mark.anyio
async def test_market_data_ingestor_uses_cryptoview():
    mock_db = MagicMock()
    mock_repo = MagicMock()
    mock_repo.save_candles.return_value = 2

    mock_cryptoview = MagicMock()
    mock_candles = [
        Candle(
            symbol="BTC/USDT",
            timeframe="1h",
            timestamp=1729209600000,
            open=68000.0,
            high=68500.0,
            low=67800.0,
            close=68200.0,
            volume=100.0,
        ),
        Candle(
            symbol="BTC/USDT",
            timeframe="1h",
            timestamp=1729213200000,
            open=68200.0,
            high=68900.0,
            low=68100.0,
            close=68800.0,
            volume=150.0,
        ),
    ]
    mock_cryptoview.fetch_candles = AsyncMock(return_value=mock_candles)

    mock_kucoin = MagicMock()

    ingestor = MarketDataIngestor(
        db_manager=mock_db,
        candle_repo=mock_repo,
        cryptoview_client=mock_cryptoview,
        kucoin_client=mock_kucoin,
        symbols=["BTC/USDT"],
        use_cryptoview=True,
    )

    saved = await ingestor.sync_once()

    assert saved == 2
    mock_cryptoview.fetch_candles.assert_called_once_with(
        symbol="BTC/USDT",
        timeframe="1h",
        exchange="kucoin",
        limit=5,
        auto_track=True,
    )
    mock_repo.save_candles.assert_called_once_with(mock_candles)
    # Ensure kucoin client was not called since cryptoview succeeded
    mock_kucoin.fetch_ohlcv.assert_not_called()
