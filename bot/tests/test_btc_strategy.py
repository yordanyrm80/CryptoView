import pandas as pd
import pytest
from src.domain.models import BotConfig, MarketRegime, Tranche, TrancheStatus
from src.strategies.base import PortfolioState, SignalType
from src.strategies.btc_regime import BtcChainedRegimeStrategy


def test_btc_chained_strategy_t0_filter():
    config = BotConfig(
        bot_id="bot_btc_test",
        symbol="BTC/USDT",
        budget=1000.0,
        take_profit_pct=5.0,
        max_tranches=5,
        tranche_weights=[0.10, 0.15, 0.20, 0.25, 0.30],
        atr_multiplier=1.5,
        trailing_stop_pct=2.5,
    )
    strat = BtcChainedRegimeStrategy(config)
    portfolio = PortfolioState(symbol="BTC/USDT", total_budget=1000.0, available_usdt=1000.0)

    # 1. Precio bajo EMA 200 en Rango -> NO debe entrar T0
    row_bearish = pd.Series({
        "close": 50000.0,
        "high": 50500.0,
        "low": 49800.0,
        "ema_50": 51000.0,
        "ema_200": 55000.0,
        "atr_14": 1000.0,
        "rsi_14": 40.0,
        "adx_14": 15.0,
    })
    signals = strat.evaluate(row_bearish, portfolio)
    assert len(signals) == 0

    # 2. Precio sobre EMA 200 con RSI sano en Rango -> Debe entrar T0
    row_bullish_range = pd.Series({
        "close": 56000.0,
        "high": 56500.0,
        "low": 55800.0,
        "ema_50": 55500.0,
        "ema_200": 55000.0,
        "atr_14": 1000.0,
        "rsi_14": 45.0,
        "adx_14": 15.0,
    })
    signals = strat.evaluate(row_bullish_range, portfolio)
    assert len(signals) == 1
    assert signals[0].signal_type == SignalType.BUY_TRANCHE
    assert signals[0].tranche_index == 0


def test_btc_chained_spacing_progression():
    config = BotConfig(
        bot_id="bot_btc_test",
        symbol="BTC/USDT",
        budget=1000.0,
        take_profit_pct=5.0,
        max_tranches=5,
        tranche_weights=[0.10, 0.15, 0.20, 0.25, 0.30],
        atr_multiplier=1.5,
        trailing_stop_pct=2.5,
    )
    strat = BtcChainedRegimeStrategy(config)
    portfolio = PortfolioState(symbol="BTC/USDT", total_budget=1000.0, available_usdt=900.0)

    # Simular Tramo 0 activo comprado a $60,000
    t0 = Tranche(
        bot_id="bot_btc_test",
        symbol="BTC/USDT",
        tranche_index=0,
        allocated_budget=100.0,
        buy_price=60000.0,
        amount=100.0 / 60000.0,
        target_sell_price=63000.0,
        status=TrancheStatus.ACTIVE,
        buy_timestamp=1000,
    )
    portfolio.active_tranches.append(t0)

    # ATR = 1,000. Tramo 1 requiere k1 = 2.0 -> 2,000 de caída desde T0 ($58,000)
    # A $58,500 NO debe comprar
    row_not_enough = pd.Series({
        "close": 58500.0,
        "high": 58800.0,
        "low": 58200.0,
        "ema_50": 59000.0,
        "ema_200": 55000.0,
        "atr_14": 1000.0,
        "rsi_14": 40.0,
        "adx_14": 15.0,
    })
    signals = strat.evaluate(row_not_enough, portfolio)
    assert len(signals) == 0

    # A $57,900 SI debe comprar Tramo 1
    row_drop_t1 = pd.Series({
        "close": 57900.0,
        "high": 58100.0,
        "low": 57500.0,
        "ema_50": 59000.0,
        "ema_200": 55000.0,
        "atr_14": 1000.0,
        "rsi_14": 38.0,
        "adx_14": 15.0,
    })
    signals = strat.evaluate(row_drop_t1, portfolio)
    assert len(signals) == 1
    assert signals[0].signal_type == SignalType.BUY_TRANCHE
    assert signals[0].tranche_index == 1
