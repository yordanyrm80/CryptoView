import pandas as pd
import pytest

from src.domain.models import BotConfig, MarketRegime, Tranche, TrancheStatus
from src.simulation.engine import SimulationEngine
from src.strategies.base import ActionSignal, PortfolioState, SignalType
from src.strategies.btc_quantum_satoshi_regime import BtcQuantumSatoshiRegimeStrategy


def test_quantum_satoshi_sniper_unlocked():
    """Verifica que el francotirador de pánico dispare ante RSI < 28 aunque existan tranches previos ocupados."""
    config = BotConfig(
        bot_id="btc_satoshi_test",
        symbol="BTC/USDT",
        budget=1000.0,
        take_profit_pct=5.0,
        max_tranches=5,
        tranche_weights=[0.30, 0.25, 0.20, 0.15, 0.10],
    )
    strat = BtcQuantumSatoshiRegimeStrategy(config)

    # Simular una vela de pánico severo
    row_panic = pd.Series({
        "close": 20000.0,
        "high": 20200.0,
        "low": 19800.0,
        "ema_50": 25000.0,
        "ema_200": 30000.0,
        "rsi_14": 22.0,  # Sobreventa extrema
        "adx_14": 15.0,
        "atr_14": 500.0,
        "ema_daily_200": 32000.0,
    })

    # Cartera con tramo 0 ya ocupado
    t0 = Tranche(
        bot_id="btc_satoshi_test",
        symbol="BTC/USDT",
        tranche_index=0,
        allocated_budget=300.0,
        buy_price=60000.0,
        amount=300.0 / 60000.0,
        target_sell_price=63000.0,
        status=TrancheStatus.ACTIVE,
    )

    portfolio = PortfolioState(
        symbol="BTC/USDT",
        total_budget=1000.0,
        available_usdt=700.0,
        active_tranches=[t0],
    )

    signals = strat.evaluate(row_panic, portfolio)
    assert len(signals) == 1
    sig = signals[0]
    assert sig.signal_type == SignalType.BUY_TRANCHE
    assert sig.tranche_index == BtcQuantumSatoshiRegimeStrategy.INDICE_SNIPER
    assert sig.target_sell_price == pytest.approx(20000.0 * 1.07)


def test_quantum_satoshi_recycling_increases_btc():
    """Verifica que el reciclaje en Satoshis agregue delta BTC al tramo colgado y reduzca su breakeven."""
    config = BotConfig(
        bot_id="btc_satoshi_test",
        symbol="BTC/USDT",
        budget=1000.0,
        take_profit_pct=5.0,
        max_tranches=5,
        tranche_weights=[0.30, 0.25, 0.20, 0.15, 0.10],
    )
    strat = BtcQuantumSatoshiRegimeStrategy(config)

    engine = SimulationEngine(
        fee_rate=0.001,
        enable_profit_recycling=True,
        satoshi_recycling=True,
        harvest_mode="SATOSHIS",
        recycle_profit_fraction=0.35,
    )

    # 1. Tramo colgado a 50k
    t_colgado = Tranche(
        bot_id="btc_satoshi_test",
        symbol="BTC/USDT",
        tranche_index=0,
        allocated_budget=300.0,
        buy_price=50000.0,
        amount=300.0 / 50000.0,  # 0.006 BTC
        target_sell_price=52500.0,
        status=TrancheStatus.ACTIVE,
    )

    # 2. Tramo inferior que va a cerrar con ganancia en el fondo
    t_inferior = Tranche(
        bot_id="btc_satoshi_test",
        symbol="BTC/USDT",
        tranche_index=1,
        allocated_budget=250.0,
        buy_price=20000.0,
        amount=250.0 / 20000.0,  # 0.0125 BTC
        target_sell_price=21000.0,  # +5%
        status=TrancheStatus.ACTIVE,
    )

    cant_inicial_colgado = t_colgado.amount

    # Crear dataset sintético de 2 velas: la segunda toca 21000 para vender t_inferior
    df_sim = pd.DataFrame([
        {
            "timestamp": 1600000000000,
            "open": 20000.0,
            "high": 20500.0,
            "low": 19900.0,
            "close": 20000.0,
            "volume": 100.0,
            "ema_50": 20000.0,
            "ema_200": 30000.0,
            "rsi_14": 40.0,
            "adx_14": 15.0,
            "atr_14": 500.0,
            "ema_daily_200": 32000.0,
        },
        {
            "timestamp": 1600003600000,
            "open": 20000.0,
            "high": 21500.0,  # Ejecuta TP de t_inferior
            "low": 20000.0,
            "close": 21000.0,
            "volume": 100.0,
            "ema_50": 20000.0,
            "ema_200": 30000.0,
            "rsi_14": 45.0,
            "adx_14": 15.0,
            "atr_14": 500.0,
            "ema_daily_200": 32000.0,
        },
    ])

    # MockStrat que compra T0 (arriba) y T1 (abajo) en la vela 0, y vende T1 con beneficio en la vela 1
    class MockStrat(BtcQuantumSatoshiRegimeStrategy):
        def evaluate(self, row, portfolio):
            if row["timestamp"] == 1600000000000:
                # Comprar T0 a 50k (colgado) y T1 a 20k
                return [
                    ActionSignal(
                        signal_type=SignalType.BUY_TRANCHE,
                        symbol="BTC/USDT",
                        tranche_index=0,
                        price=50000.0,
                        amount=300.0 / 50000.0,
                        allocated_usdt=300.0,
                        target_sell_price=52500.0,
                    ),
                    ActionSignal(
                        signal_type=SignalType.BUY_TRANCHE,
                        symbol="BTC/USDT",
                        tranche_index=1,
                        price=20000.0,
                        amount=250.0 / 20000.0,
                        allocated_usdt=250.0,
                        target_sell_price=21000.0,
                    ),
                ]
            elif row["timestamp"] == 1600003600000:
                # Vender T1 a 21k (ganancia de $12.50)
                for t in list(portfolio.active_tranches):
                    if t.tranche_index == 1:
                        return [
                            ActionSignal(
                                signal_type=SignalType.SELL_TRANCHE,
                                symbol="BTC/USDT",
                                tranche_index=1,
                                price=21000.0,
                                amount=t.amount,
                                allocated_usdt=t.allocated_budget,
                                reason="TP",
                                tranche_ref=t,
                            )
                        ]
            return []

    mock_strat = MockStrat(config)
    metricas, _, completados = engine.run(mock_strat, df_sim, initial_capital=1000.0)

    assert metricas.total_trades == 1
    assert metricas.accumulated_satoshis > 0.0
