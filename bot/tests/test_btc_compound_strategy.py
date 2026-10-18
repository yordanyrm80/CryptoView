import pandas as pd
import pytest
from src.domain.models import BotConfig, MarketRegime, Tranche, TrancheStatus
from src.strategies.base import PortfolioState, SignalType
from src.strategies.btc_compound_regime import BtcCompoundRegimeStrategy


def test_btc_compound_strategy_dynamic_budget():
    config = BotConfig(
        bot_id="bot_btc_compound_test",
        symbol="BTC/USDT",
        budget=1000.0,
        take_profit_pct=5.0,
        max_tranches=5,
        tranche_weights=[0.25, 0.20, 0.20, 0.20, 0.15],
        atr_multiplier=1.5,
        trailing_stop_pct=2.5,
    )
    strat = BtcCompoundRegimeStrategy(config, enable_compounding=True)

    # 1. Sin ganancias previas: effective_base = $1,000. T0 weight = 0.25 -> $250
    portfolio = PortfolioState(symbol="BTC/USDT", total_budget=1000.0, available_usdt=1000.0)
    portfolio.total_realized_profit = 0.0

    row_bullish = pd.Series({
        "close": 60000.0,
        "high": 60500.0,
        "low": 59800.0,
        "ema_50": 58000.0,
        "ema_200": 55000.0,
        "atr_14": 1000.0,
        "rsi_14": 42.0,
        "adx_14": 15.0,
    })

    signals = strat.evaluate(row_bullish, portfolio)
    assert len(signals) == 1
    assert signals[0].signal_type == SignalType.BUY_TRANCHE
    assert signals[0].tranche_index == 0
    assert pytest.approx(signals[0].allocated_usdt, 0.01) == 250.0  # 25% de $1,000

    # 2. Con $1,000 de ganancia realizada: effective_base = $2,000. T0 weight = 0.25 -> $500
    portfolio_rich = PortfolioState(symbol="BTC/USDT", total_budget=2000.0, available_usdt=2000.0)
    portfolio_rich.total_realized_profit = 1000.0

    signals_rich = strat.evaluate(row_bullish, portfolio_rich)
    assert len(signals_rich) == 1
    assert pytest.approx(signals_rich[0].allocated_usdt, 0.01) == 500.0  # 25% de $2,000!


def test_btc_compound_strategy_chained_spacing():
    config = BotConfig(
        bot_id="bot_btc_compound_test",
        symbol="BTC/USDT",
        budget=1000.0,
        take_profit_pct=5.0,
        max_tranches=5,
        tranche_weights=[0.25, 0.20, 0.20, 0.20, 0.15],
        atr_multiplier=1.5,
        trailing_stop_pct=2.5,
    )
    strat = BtcCompoundRegimeStrategy(config, enable_compounding=True)
    portfolio = PortfolioState(symbol="BTC/USDT", total_budget=1000.0, available_usdt=750.0)

    # Simular T0 comprado a $60,000
    t0 = Tranche(
        bot_id="bot_btc_compound_test",
        symbol="BTC/USDT",
        tranche_index=0,
        allocated_budget=250.0,
        buy_price=60000.0,
        amount=250.0 / 60000.0,
        target_sell_price=63000.0,
        status=TrancheStatus.ACTIVE,
        buy_timestamp=1000,
    )
    portfolio.active_tranches.append(t0)

    # Con ATR = 1,000, T1 requiere caída de 2.0 * ATR = $2,000 -> target $58,000
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
    assert signals[0].tranche_index == 1
    assert pytest.approx(signals[0].allocated_usdt, 0.01) == 200.0  # 20% de $1,000
