import pandas as pd
import pytest
from src.domain.models import BotConfig, Tranche, TrancheStatus
from src.strategies.base import PortfolioState, SignalType
from src.strategies.btc_macro_compound_regime import BtcMacroCompoundRegimeStrategy


@pytest.fixture
def base_config():
    return BotConfig(
        bot_id="bot_btc_macro_test",
        symbol="BTC/USDT",
        budget=1000.0,
        take_profit_pct=5.0,
        max_tranches=5,
        tranche_weights=[0.25, 0.20, 0.20, 0.20, 0.15],
        atr_multiplier=1.5,
        trailing_stop_pct=2.5,
    )


def test_btc_macro_filter_blocks_entry_below_daily_ema(base_config):
    """Verifica que si el precio está por debajo de Daily EMA 200, NO se abre Tramo 0,

    incluso si supera la EMA 200 de 1 hora (evitando trampas de mercado bajista).
    """
    strat = BtcMacroCompoundRegimeStrategy(base_config, enable_compounding=True, macro_indicator="ema_daily_200")
    portfolio = PortfolioState(symbol="BTC/USDT", total_budget=1000.0, available_usdt=1000.0)

    # Vela de rebote engañoso (Bear Trap):
    # Precio ($35,000) > EMA 200 1h ($34,000), pero < Daily EMA 200 ($42,000)
    row_bear_trap = pd.Series({
        "close": 35000.0,
        "high": 35500.0,
        "low": 34800.0,
        "ema_50": 34500.0,
        "ema_200": 34000.0,
        "ema_4h_200": 38000.0,
        "ema_daily_200": 42000.0,
        "atr_14": 800.0,
        "rsi_14": 45.0,
        "adx_14": 18.0,
    })

    signals = strat.evaluate(row_bear_trap, portfolio)
    # Debe ser bloqueado por el filtro macro
    assert len(signals) == 0


def test_btc_macro_filter_allows_entry_above_daily_ema(base_config):
    """Verifica que si el precio confirma estructura sobre Daily EMA 200 y RSI < 48,

    se ejecuta la orden de compra de Tramo 0.
    """
    strat = BtcMacroCompoundRegimeStrategy(base_config, enable_compounding=True, macro_indicator="ema_daily_200")
    portfolio = PortfolioState(symbol="BTC/USDT", total_budget=1000.0, available_usdt=1000.0)

    # Vela en mercado alcista macro:
    # Precio ($45,000) > Daily EMA 200 ($42,000) y RSI < 48
    row_bull_confirmed = pd.Series({
        "close": 45000.0,
        "high": 45500.0,
        "low": 44800.0,
        "ema_50": 43500.0,
        "ema_200": 41000.0,
        "ema_4h_200": 41500.0,
        "ema_daily_200": 42000.0,
        "atr_14": 800.0,
        "rsi_14": 42.0,
        "adx_14": 18.0,
    })

    signals = strat.evaluate(row_bull_confirmed, portfolio)
    assert len(signals) == 1
    assert signals[0].signal_type == SignalType.BUY_TRANCHE
    assert signals[0].tranche_index == 0
    assert pytest.approx(signals[0].allocated_usdt, 0.01) == 250.0  # 25% de $1,000


def test_btc_macro_allows_chained_recovery_tranches(base_config):
    """Verifica que una vez que T0 está activo, las compras de rescate encadenadas (T1-T4)

    sigan operando para promediar y tomar beneficios en los rebotes, sin ser bloqueadas.
    """
    strat = BtcMacroCompoundRegimeStrategy(base_config, enable_compounding=True, macro_indicator="ema_daily_200")
    portfolio = PortfolioState(symbol="BTC/USDT", total_budget=1000.0, available_usdt=750.0)

    # Simular T0 ya abierto a $45,000
    t0 = Tranche(
        bot_id="bot_btc_macro_test",
        symbol="BTC/USDT",
        tranche_index=0,
        allocated_budget=250.0,
        buy_price=45000.0,
        amount=250.0 / 45000.0,
        target_sell_price=47250.0,
        status=TrancheStatus.ACTIVE,
        buy_timestamp=1000,
    )
    portfolio.active_tranches.append(t0)

    # Precio cae 2.0x ATR ($1,600) -> Target <= $43,400.
    # Supongamos que el precio cae a $43,000, por debajo de Daily EMA 200 ($44,000)
    row_chained_drop = pd.Series({
        "close": 43000.0,
        "high": 43200.0,
        "low": 42800.0,
        "ema_50": 44000.0,
        "ema_200": 44200.0,
        "ema_4h_200": 44100.0,
        "ema_daily_200": 44000.0,
        "atr_14": 800.0,
        "rsi_14": 35.0,
        "adx_14": 15.0,
    })

    signals = strat.evaluate(row_chained_drop, portfolio)
    assert len(signals) == 1
    assert signals[0].signal_type == SignalType.BUY_TRANCHE
    assert signals[0].tranche_index == 1
    assert pytest.approx(signals[0].allocated_usdt, 0.01) == 200.0  # 20% de $1,000
