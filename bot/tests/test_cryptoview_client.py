import pytest
from unittest.mock import AsyncMock, patch, MagicMock
from src.exchange.cryptoview_client import CryptoViewClient
from src.domain.models import Candle


@pytest.mark.anyio
async def test_cryptoview_client_fetch_candles_mapping():
    client = CryptoViewClient(base_url="https://fake-engine.local", api_key="test-key")

    mock_response = [
        {
            "time": 1729209600,
            "open": 68000.5,
            "high": 68500.0,
            "low": 67800.25,
            "close": 68250.75,
            "volume": 124.55,
        },
        {
            "time": 1729213200,
            "open": 68250.75,
            "high": 69000.0,
            "low": 68100.0,
            "close": 68900.0,
            "volume": 210.12,
        },
    ]

    mock_resp_obj = MagicMock()
    mock_resp_obj.status_code = 200
    mock_resp_obj.json.return_value = mock_response

    with patch("httpx.AsyncClient.get", new_callable=AsyncMock) as mock_get:
        mock_get.return_value = mock_resp_obj

        candles = await client.fetch_candles("BTC/USDT", timeframe="1h", exchange="kucoin", limit=10)

        assert len(candles) == 2
        first = candles[0]
        assert isinstance(first, Candle)
        assert first.symbol == "BTC/USDT"
        assert first.timeframe == "1h"
        assert first.timestamp == 1729209600 * 1000  # Converted to milliseconds
        assert first.open == 68000.5
        assert first.high == 68500.0
        assert first.low == 67800.25
        assert first.close == 68250.75
        assert first.volume == 124.55


@pytest.mark.anyio
async def test_cryptoview_client_health():
    client = CryptoViewClient(base_url="https://fake-engine.local", api_key="test-key")

    mock_health = {
        "status": "online",
        "database": "connected (TimescaleDB / PostgreSQL 17)",
        "worker_status": "online",
        "total_candles_stored": 2850000,
    }

    mock_resp_obj = MagicMock()
    mock_resp_obj.status_code = 200
    mock_resp_obj.json.return_value = mock_health

    with patch("httpx.AsyncClient.get", new_callable=AsyncMock) as mock_get:
        mock_get.return_value = mock_resp_obj
        res = await client.check_health()
        assert res["status"] == "online"
        assert res["total_candles_stored"] == 2850000
