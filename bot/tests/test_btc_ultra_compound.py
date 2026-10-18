import pandas as pd
import pytest
from src.domain.models import BotConfig, Tranche, TrancheStatus
from src.strategies.base import PortfolioState, SignalType
from src.strategies.btc_ultra_compound_regime import BtcUltraCompoundRegimeStrategy


def test_btc_ultra_compound_weights_and_trailing():
    config = BotConfig(
        bot_id="bot_btc_ultra_test",
        symbol="BTC/USDT",
        budget=1000.0,
        take_profit_pct=5.0,
        max_tranches=5,
        tranche_weights=[0.30, 0.25, 0.20, 0.15, 0.10],
        atr_multiplier=1.5,
        trailing_stop_pct=2.0,
    )
    strat = BtcUltraCompoundRegimeStrategy(config, enable_compounding=True, trailing_stop_pct=2.0)
    portfolio = PortfolioState(symbol="BTC/USDT", total_budget=1000.0, available_usdt=1000.0)

    # Vela en Rango con precio sobre Daily EMA 200
    row_range = pd.Series({
        "close": 50000.0,
        "high": 50500.0,
        "low": 49800.0,
        "ema_50": 48000.0,
        "ema_200": 47000.0,
        "ema_daily_200": 46000.0,
        "atr_14": 1000.0,
        "rsi_14": 42.0,
        "adx_14": 15.0,
    })

    signals = strat.evaluate(row_range, portfolio)
    assert len(signals) == 1
    assert signals[0].signal_type == SignalType.BUY_TRANCHE
    assert signals[0].tranche_index == 0
    # Peso T0 = 30% de $1,000 = $300.0
    assert pytest.approx(signals[0].allocated_usdt, 0.01) == 300.0
