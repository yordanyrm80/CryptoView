import pytest
from fastapi.testclient import TestClient
from src.api.app import app
from src.api.services.bot_service import BotService
from src.domain.models import BotConfig, Tranche, TrancheStatus
from src.strategies.base import PortfolioState, SignalType
from src.strategies.btc_quantum_compound_regime import BtcQuantumCompoundRegimeStrategy
from src.strategies.btc_quantum_evolution_regime import BtcQuantumEvolutionRegimeStrategy
import pandas as pd


@pytest.fixture
def client():
    return TestClient(app)


def test_deposit_and_withdrawal_endpoints(client):
    """Verifica que los endpoints de depósito y retiro actualicen el balance y persistan transacciones."""
    bot_id = "apex_titan_btc"
    service = BotService.get_instance()
    bot = service.bots[bot_id]
    saldo_inicial = bot.available_usdt

    # 1. Depósito de 500 USDT
    resp_dep = client.post(f"/api/v1/bots/{bot_id}/deposit", json={"amount": 500.0, "reason": "Aporte de capital fresco"})
    assert resp_dep.status_code == 200
    data_dep = resp_dep.json()
    assert data_dep["type"] == "DEPOSIT"
    assert data_dep["amount"] == 500.0
    assert data_dep["available_usdt_after"] == pytest.approx(saldo_inicial + 500.0)

    # 2. Retiro de 300 USDT
    resp_ret = client.post(f"/api/v1/bots/{bot_id}/withdraw", json={"amount": 300.0, "reason": "Cosecha de beneficios"})
    assert resp_ret.status_code == 200
    data_ret = resp_ret.json()
    assert data_ret["type"] == "WITHDRAWAL"
    assert data_ret["amount"] == 300.0
    assert data_ret["available_usdt_after"] == pytest.approx(saldo_inicial + 200.0)

    # 3. Intentar retirar más del disponible debe arrojar 400 Bad Request
    resp_err = client.post(f"/api/v1/bots/{bot_id}/withdraw", json={"amount": 999999.0, "reason": "Retiro excesivo"})
    assert resp_err.status_code == 400
    assert "Fondos insuficientes" in resp_err.json()["detail"]

    # 4. Historial de transacciones de capital
    resp_tx = client.get(f"/api/v1/bots/{bot_id}/transactions")
    assert resp_tx.status_code == 200
    txs = resp_tx.json()
    assert len(txs) >= 2
    assert any(t["type"] == "DEPOSIT" and t["amount"] == 500.0 for t in txs)
    assert any(t["type"] == "WITHDRAWAL" and t["amount"] == 300.0 for t in txs)


def test_bot_events_audit_log(client):
    """Verifica que pausar, reanudar y mover capital genere bitácora transparente de auditoría."""
    bot_id = "apex_titan_btc"

    client.post(f"/api/v1/bots/{bot_id}/pause")
    client.post(f"/api/v1/bots/{bot_id}/resume")

    resp_ev = client.get(f"/api/v1/bots/{bot_id}/events")
    assert resp_ev.status_code == 200
    events = resp_ev.json()
    tipos = [e["event_type"] for e in events]
    assert "PAUSED" in tipos
    assert "RESUMED" in tipos


def test_plateau_phase_status(client):
    """Verifica que el endpoint de estado de meseta diagnostique si es apto incorporar capital."""
    bot_id = "apex_titan_btc"
    resp = client.get(f"/api/v1/bots/{bot_id}/plateau-status")
    assert resp.status_code == 200
    data = resp.json()
    assert "is_plateau_phase" in data
    assert "capital_injection_recommended" in data
    assert "advice" in data
    assert len(data["advice"]) > 0


def test_strategy_effective_base_with_capital_adjustments():
    """Verifica que la estrategia ajuste la base compuesta restando retiros y sumando depósitos."""
    config = BotConfig(
        bot_id="btc_test_base",
        symbol="BTC/USDT",
        budget=1000.0,
        take_profit_pct=4.5,
        trend_weight=0.70,
    )
    strat = BtcQuantumEvolutionRegimeStrategy(config)

    # Vela en tendencia alcista
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

    # Caso 1: Presupuesto 1000 + Beneficio 400 - Retiros 100 = Base 1300 -> 70% de 1300 = 910 USDT
    cartera_1 = PortfolioState(
        symbol="BTC/USDT",
        total_budget=1000.0,
        available_usdt=1300.0,
        total_realized_profit=400.0,
        total_withdrawn_amount=100.0,
        total_deposited_amount=0.0,
        active_tranches=[],
    )
    sig_1 = strat.evaluate(row_trend, cartera_1)
    assert len(sig_1) == 1
    assert sig_1[0].allocated_usdt == pytest.approx(910.0)

    # Caso 2: Presupuesto 1000 + Depósito 500 = Base 1500 -> 70% de 1500 = 1050 USDT
    cartera_2 = PortfolioState(
        symbol="BTC/USDT",
        total_budget=1000.0,
        available_usdt=1500.0,
        total_realized_profit=0.0,
        total_withdrawn_amount=0.0,
        total_deposited_amount=500.0,
        active_tranches=[],
    )
    sig_2 = strat.evaluate(row_trend, cartera_2)
    assert len(sig_2) == 1
    assert sig_2[0].allocated_usdt == pytest.approx(1050.0)


@pytest.mark.anyio
async def test_live_runner_auto_reconciliation():
    """Verifica que EjecutorEnVivo detecte automáticamente discrepancias de saldo con KuCoin."""
    from src.core.live_runner import LiveRunner

    class MockKuCoinClient:
        def __init__(self, saldo: float):
            self.saldo = saldo

        def fetch_free_balance(self, currency: str = "USDT"):
            return self.saldo

    service = BotService.get_instance()
    bot = service.bots["apex_titan_btc"]
    # Simular que el bot no está en dry run
    bot.dry_run = False
    bot.available_usdt = 1000.0
    bot.total_withdrawn_amount = 0.0

    # Simular que en KuCoin el usuario retiró 200 USDT (saldo real en exchange = 800)
    mock_client = MockKuCoinClient(saldo=800.0)
    runner = LiveRunner(
        bot_service=service,
        interval_seconds=1.0,
    )
    runner.set_exchange_client(bot.config.bot_id, mock_client)

    await runner.run_cycle()

    assert bot.available_usdt == 800.0
    assert bot.total_withdrawn_amount == 200.0

    # Restaurar bot para no afectar otros tests
    bot.dry_run = True
