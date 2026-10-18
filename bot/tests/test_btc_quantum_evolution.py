import pandas as pd
import pytest

from src.domain.models import BotConfig, MarketRegime, Tranche, TrancheStatus
from src.simulation.engine import SimulationEngine
from src.strategies.base import PortfolioState, SignalType
from src.strategies.btc_quantum_evolution_regime import BtcQuantumEvolutionRegimeStrategy


def test_quantum_evolution_floor_tranche_activation():
    """Verifica que BtcQuantumEvolution active tramos de suelo automáticamente cuando la base está agotada y hay liquidez disponible."""
    config = BotConfig(
        bot_id="btc_evolution_test",
        symbol="BTC/USDT",
        budget=1000.0,
        take_profit_pct=5.0,
        max_tranches=5,
        tranche_weights=[0.30, 0.25, 0.20, 0.15, 0.10],
        trailing_stop_pct=2.0,
    )
    strat = BtcQuantumEvolutionRegimeStrategy(config)

    # 5 tramos base ya ocupados
    active = [
        Tranche(
            bot_id="btc_evolution_test",
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

    # Vela en rango en el pozo ($20,000, muy por debajo de 30k)
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

    # Cartera con saldo remanente ($200 USDT disponibles)
    portfolio_liquid = PortfolioState(
        symbol="BTC/USDT",
        total_budget=1200.0,
        available_usdt=200.0,
        active_tranches=active,
    )

    signals = strat.evaluate(row_floor, portfolio_liquid)
    assert len(signals) == 1
    sig = signals[0]
    assert sig.signal_type == SignalType.BUY_TRANCHE
    assert sig.tranche_index == 5  # T5 (primer tramo de suelo)
    assert "SUELO EVOLUTION" in sig.reason


def test_quantum_evolution_no_liquidity():
    """Verifica que si no hay suficiente saldo remanente (< 25 USDT), no se abran tramos de suelo."""
    config = BotConfig(
        bot_id="btc_evolution_test",
        symbol="BTC/USDT",
        budget=1000.0,
        take_profit_pct=5.0,
        max_tranches=5,
        tranche_weights=[0.30, 0.25, 0.20, 0.15, 0.10],
    )
    strat = BtcQuantumEvolutionRegimeStrategy(config)

    active = [
        Tranche(
            bot_id="btc_evolution_test",
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

    portfolio_dry = PortfolioState(
        symbol="BTC/USDT",
        total_budget=1000.0,
        available_usdt=10.0,  # Insuficiente (< 25.0)
        active_tranches=active,
    )

    signals = strat.evaluate(row_floor, portfolio_dry)
    assert len(signals) == 0


def test_quantum_evolution_configurable_parameters():
    """Verifica que peso_tendencia, trailing_stop_pct y umbrales sean configurables dinámicamente."""
    # 1. Por defecto: peso_tendencia = 0.70 y trailing_stop_pct = 1.4
    cfg_default = BotConfig(
        bot_id="btc_test_default",
        symbol="BTC/USDT",
        budget=1000.0,
        take_profit_pct=4.5,
    )
    strat_default = BtcQuantumEvolutionRegimeStrategy(cfg_default)
    assert strat_default.peso_tendencia == 0.70
    assert strat_default.porcentaje_trailing_stop == 1.4

    # 2. Configurado mediante BotConfig
    cfg_custom = BotConfig(
        bot_id="btc_test_custom",
        symbol="BTC/USDT",
        budget=1000.0,
        take_profit_pct=4.5,
        trend_weight=0.55,
        trailing_stop_pct=1.8,
    )
    strat_custom = BtcQuantumEvolutionRegimeStrategy(cfg_custom)
    assert strat_custom.peso_tendencia == 0.55
    assert strat_custom.porcentaje_trailing_stop == 1.8

    # 3. Configurado mediante kwargs directos en la estrategia
    strat_direct = BtcQuantumEvolutionRegimeStrategy(
        cfg_default,
        peso_tendencia=0.65,
        trailing_stop_pct=1.3,
        umbral_rsi_t0=45.0,
    )
    assert strat_direct.peso_tendencia == 0.65
    assert strat_direct.porcentaje_trailing_stop == 1.3
    assert strat_direct.umbral_rsi_t0 == 45.0

    # 4. Verificar que la orden de tendencia respete el peso configurado (65% de $1000 = $650)
    row_trend = pd.Series({
        "close": 50000.0,
        "high": 50500.0,
        "low": 49800.0,
        "ema_50": 49000.0,
        "ema_200": 40000.0,
        "rsi_14": 52.0,
        "adx_14": 30.0,
        "atr_14": 1000.0,
        "ema_daily_200": 38000.0,
    })
    portfolio_empty = PortfolioState(
        symbol="BTC/USDT",
        total_budget=1000.0,
        available_usdt=1000.0,
        active_tranches=[],
    )
    signals = strat_direct.evaluate(row_trend, portfolio_empty)
    assert len(signals) == 1
    assert signals[0].signal_type == SignalType.BUY_TRANCHE
    assert signals[0].allocated_usdt == pytest.approx(650.0)

