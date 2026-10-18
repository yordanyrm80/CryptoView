import pandas as pd
import pytest
from src.domain.models import BotConfig, Tranche, TrancheStatus
from src.strategies.base import PortfolioState, SignalType
from src.strategies.btc_quantum_compound_regime import BtcQuantumCompoundRegimeStrategy


def test_btc_quantum_strategy_weights():
    """Verifica que el Tramo 0 conserva estrictamente el 30% del presupuesto."""
    config = BotConfig(
        bot_id="bot_btc_quantum_test",
        symbol="BTC/USDT",
        budget=1000.0,
        take_profit_pct=5.0,
        max_tranches=5,
        tranche_weights=[0.30, 0.25, 0.20, 0.15, 0.10],
        atr_multiplier=1.5,
        trailing_stop_pct=2.0,
    )
    strat = BtcQuantumCompoundRegimeStrategy(config, enable_compounding=True)
    portfolio = PortfolioState(symbol="BTC/USDT", total_budget=1000.0, available_usdt=1000.0)

    # Vela en rango sobre Daily EMA 200
    row = pd.Series({
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

    signals = strat.evaluate(row, portfolio)
    assert len(signals) == 1
    assert signals[0].signal_type == SignalType.BUY_TRANCHE
    assert signals[0].tranche_index == 0
    # Peso T0 = 30% de $1,000 = $300
    assert pytest.approx(signals[0].allocated_usdt, 0.01) == 300.0


def test_btc_quantum_sniper_threshold():
    """Verifica que el francotirador responde a RSI < 28 en capitulaciones."""
    config = BotConfig(
        bot_id="bot_btc_quantum_test",
        symbol="BTC/USDT",
        budget=1000.0,
        take_profit_pct=5.0,
        max_tranches=5,
        tranche_weights=[0.30, 0.25, 0.20, 0.15, 0.10],
        atr_multiplier=1.5,
        trailing_stop_pct=2.0,
    )
    strat = BtcQuantumCompoundRegimeStrategy(config, enable_compounding=True, panic_rsi_threshold=28.0)
    portfolio = PortfolioState(symbol="BTC/USDT", total_budget=1000.0, available_usdt=1000.0)

    # Vela de pánico severo con RSI = 27 (menor a 28)
    row_panic = pd.Series({
        "close": 30000.0,
        "high": 31000.0,
        "low": 29000.0,
        "ema_50": 35000.0,
        "ema_200": 38000.0,
        "ema_daily_200": 42000.0,
        "atr_14": 2000.0,
        "rsi_14": 27.0,
        "adx_14": 30.0,
    })

    signals = strat.evaluate(row_panic, portfolio)
    assert len(signals) == 1
    assert signals[0].signal_type == SignalType.BUY_TRANCHE
    assert signals[0].tranche_index == 0
    # Asigna 35% sniper = $350
    assert pytest.approx(signals[0].allocated_usdt, 0.01) == 350.0


def test_cascading_subsidized_discount():
    """Verifica que el descuento subsidiado fluye en cascada cuando el tramo más alto toca su floor."""
    from src.simulation.engine import SimulationEngine
    from src.strategies.base import ActionSignal, BaseStrategy

    class MockStrategy(BaseStrategy):
        def __init__(self, cfg):
            super().__init__(cfg)
            self.step = 0

        def evaluate(self, row, portfolio):
            self.step += 1
            if self.step == 1:
                # Comprar T0 a 60,000
                return [ActionSignal(SignalType.BUY_TRANCHE, "BTC/USDT", 0, 60000.0, 300.0 / 60000.0, 300.0, "T0", target_sell_price=63000.0)]
            elif self.step == 2:
                # Comprar T1 a 50,000
                return [ActionSignal(SignalType.BUY_TRANCHE, "BTC/USDT", 1, 50000.0, 250.0 / 50000.0, 250.0, "T1", target_sell_price=52500.0)]
            elif self.step == 3:
                # Comprar T2 a 40,000
                return [ActionSignal(SignalType.BUY_TRANCHE, "BTC/USDT", 2, 40000.0, 200.0 / 40000.0, 200.0, "T2", target_sell_price=42000.0)]
            elif self.step == 4:
                # Vender T2 a 45,000 (ganancia para probar cascada)
                t2 = [t for t in portfolio.active_tranches if t.tranche_index == 2][0]
                return [ActionSignal(SignalType.SELL_TRANCHE, "BTC/USDT", 2, 45000.0, t2.amount, t2.allocated_budget, "TP T2", tranche_ref=t2)]
            elif self.step == 5:
                # Verificar que el target de T0 fue descontado
                t0 = [t for t in portfolio.active_tranches if t.tranche_index == 0][0]
                assert t0.target_sell_price < 63000.0
                assert t0.target_sell_price >= 60000.0 * (1.0 - 0.12)
            return []

    config = BotConfig(
        bot_id="bot_mock",
        symbol="BTC/USDT",
        budget=1000.0,
        take_profit_pct=5.0,
        max_tranches=5,
        tranche_weights=[0.30, 0.25, 0.20, 0.15, 0.10],
    )
    engine = SimulationEngine(
        enable_profit_recycling=True,
        allow_subsidized_discount=True,
        max_subsidized_discount_pct=0.12,
        recycle_profit_fraction=0.35,
        enable_cascading_discount=True,
    )
    df_dummy = pd.DataFrame([
        {"timestamp": 1000, "close": 60000.0, "high": 60500.0, "low": 59500.0},
        {"timestamp": 2000, "close": 50000.0, "high": 50500.0, "low": 49500.0},
        {"timestamp": 3000, "close": 40000.0, "high": 40500.0, "low": 39500.0},
        {"timestamp": 4000, "close": 45000.0, "high": 45500.0, "low": 44500.0},
        {"timestamp": 5000, "close": 46000.0, "high": 46500.0, "low": 45500.0},
    ])
    strat = MockStrategy(config)
    metrics, _, completed = engine.run(strat, df_dummy, 1000.0)

    assert strat.step == 5
    assert len(completed) == 1
    assert completed[0].tranche_index == 2

