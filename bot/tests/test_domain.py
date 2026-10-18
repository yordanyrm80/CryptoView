from datetime import datetime, timezone
import pytest
from src.domain.models import Candle, Order, OrderSide, OrderStatus, OrderType, Tranche, TrancheStatus, BotConfig


def test_candle_dt():
    ts = 1700000000000  # 2023-11-14 22:13:20 UTC
    candle = Candle(
        symbol="BTC/USDT",
        timeframe="1h",
        timestamp=ts,
        open=36000.0,
        high=36500.0,
        low=35900.0,
        close=36200.0,
        volume=120.5,
    )
    assert candle.dt == datetime.fromtimestamp(ts / 1000.0, tz=timezone.utc)
    assert candle.close == 36200.0


def test_tranche_model():
    tranche = Tranche(
        bot_id="bot_btc",
        symbol="BTC/USDT",
        tranche_index=0,
        allocated_budget=100.0,
        buy_price=50000.0,
        amount=0.002,
        target_sell_price=52500.0,
        status=TrancheStatus.ACTIVE,
    )
    assert tranche.status == TrancheStatus.ACTIVE
    assert tranche.target_sell_price == 52500.0


def test_bot_config_defaults():
    config = BotConfig(
        bot_id="bot_eth",
        symbol="ETH/USDT",
        budget=500.0,
        take_profit_pct=10.0,
    )
    assert config.max_tranches == 5
    assert len(config.tranche_weights) == 5
    assert sum(config.tranche_weights) == 1.0
