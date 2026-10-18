import pandas as pd
import pytest

from src.domain.models import BotConfig, MarketRegime, Tranche, TrancheStatus
from src.simulation.engine import SimulationEngine
from src.strategies.base import PortfolioState, SignalType
from src.strategies.btc_quantum_reload_regime import BtcQuantumReloadRegimeStrategy


def test_quantum_reload_floor_tranche_activation():
    """Verifica que los tramos de suelo se activen cuando los 5 tramos base están ocupados y hay liquidez."""
    config = BotConfig(
        bot_id="btc_reload_test",
        symbol="BTC/USDT",
        budget=1000.0,
        take_profit_pct=5.0,
        max_tranches=5,
        tranche_weights=[0.30, 0.25, 0.20, 0.15, 0.10],
    )
    strat = BtcQuantumReloadRegimeStrategy(config)

    # 5 tramos base ya ocupados
    active = [
        Tranche(
            bot_id="btc_reload_test",
            symbol="BTC/USDT",
            tranche_index=i,
            allocated_budget=200.0,
            buy_price=50000.0 - i * 5000.0,
            amount=200.0 / (50000.0 - i * 5000.0),
            target_sell_price=52500.0,
            status=TrancheStatus.ACTIVE,
        )
        for i in range(5)
    ]

    # Vela en rango en el pozo ($20,000, muy por debajo de 50k - 20k = 30k)
    row_floor = pd.Series({
        "close": 20000.0,
        "high": 20500.0,
        "low": 19500.0,
        "ema_50": 22000.0,
        "ema_200": 35000.0,
        "rsi_14": 35.0,
        "adx_14": 15.0,
        "atr_14": 800.0,
        "ema_daily_200": 40000.0,
    })

    # Caso A: Con liquidez fresca inyectada ($500 USDT disponibles)
    portfolio_liquid = PortfolioState(
        symbol="BTC/USDT",
        total_budget=1500.0,
        available_usdt=500.0,
        active_tranches=active,
    )

    signals = strat.evaluate(row_floor, portfolio_liquid)
    assert len(signals) == 1
    sig = signals[0]
    assert sig.signal_type == SignalType.BUY_TRANCHE
    assert sig.tranche_index == 5  # Primer tramo de suelo
    assert sig.allocated_usdt >= 10.0

    # Caso B: Sin liquidez (0 USDT disponibles)
    portfolio_empty = PortfolioState(
        symbol="BTC/USDT",
        total_budget=1000.0,
        available_usdt=5.0,
        active_tranches=active,
    )
    signals_empty = strat.evaluate(row_floor, portfolio_empty)
    assert len(signals_empty) == 0
