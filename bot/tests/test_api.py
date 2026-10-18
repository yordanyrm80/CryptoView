import pytest
from fastapi.testclient import TestClient
from src.api.app import app
from src.api.services.bot_service import BotService


@pytest.fixture
def client():
    # Reiniciar estado del servicio singleton y limpiar bots temporales antes de las pruebas
    from src.storage.database import DatabaseManager
    db = DatabaseManager()
    with db.get_connection() as conn:
        conn.execute("DELETE FROM bots WHERE bot_id NOT IN ('apex_titan_btc');")
    BotService._instance = None
    return TestClient(app)


def test_root_endpoint(client):
    response = client.get("/")
    assert response.status_code == 200
    data = response.json()
    assert data["name"] == "CriptoBot API"
    assert data["status"] == "online"
    assert "Tailscale" in data["network"]


def test_system_health(client):
    response = client.get("/api/v1/system/health")
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "healthy"
    assert data["database_connected"] is True
    assert "active_bots" in data


def test_list_bots(client):
    response = client.get("/api/v1/bots")
    assert response.status_code == 200
    bots = response.json()
    assert isinstance(bots, list)
    assert len(bots) >= 1
    # Verifica el bot por defecto
    default_bot = next(b for b in bots if b["bot_id"] == "apex_titan_btc")
    assert default_bot["symbol"] == "BTC/USDT"
    assert default_bot["budget"] == 1000.0
    assert default_bot["dry_run"] is True


def test_get_bot_by_id(client):
    response = client.get("/api/v1/bots/apex_titan_btc")
    assert response.status_code == 200
    data = response.json()
    assert data["bot_id"] == "apex_titan_btc"
    assert data["strategy_name"] == "BtcQuantumEvolutionRegimeStrategy"


def test_get_bot_not_found(client):
    response = client.get("/api/v1/bots/non_existent_bot")
    assert response.status_code == 404


def test_get_bot_tranches(client):
    response = client.get("/api/v1/bots/apex_titan_btc/tranches")
    assert response.status_code == 200
    tranches = response.json()
    assert isinstance(tranches, list)


def test_create_bot_success(client):
    payload = {
        "bot_id": "eth_adaptive_test",
        "symbol": "ETH/USDT",
        "strategy_name": "AdaptiveThreeRegimeStrategy",
        "budget": 500.0,
        "dry_run": True,
        "take_profit_pct": 10.0,
        "trailing_stop_pct": 2.0,
    }
    response = client.post("/api/v1/bots", json=payload)
    assert response.status_code == 201
    created = response.json()
    assert created["bot_id"] == "eth_adaptive_test"
    assert created["budget"] == 500.0

    # Verificar que aparece en la lista
    list_resp = client.get("/api/v1/bots")
    assert any(b["bot_id"] == "eth_adaptive_test" for b in list_resp.json())


def test_create_bot_duplicate_error(client):
    payload = {
        "bot_id": "apex_titan_btc",  # Ya existe
        "symbol": "BTC/USDT",
        "budget": 1000.0,
        "dry_run": True,
    }
    response = client.post("/api/v1/bots", json=payload)
    assert response.status_code == 400
    assert "already exists" in response.json()["detail"]


def test_pause_and_resume_bot(client):
    # Pausar
    pause_resp = client.post("/api/v1/bots/apex_titan_btc/pause")
    assert pause_resp.status_code == 200
    assert pause_resp.json()["status"] == "PAUSED"

    bot_resp = client.get("/api/v1/bots/apex_titan_btc")
    assert bot_resp.json()["status"] == "PAUSED"

    # Reanudar
    resume_resp = client.post("/api/v1/bots/apex_titan_btc/resume")
    assert resume_resp.status_code == 200
    assert resume_resp.json()["status"] == "RUNNING"


    bot_resp2 = client.get("/api/v1/bots/apex_titan_btc")
    assert bot_resp2.json()["status"] == "RUNNING"


def test_start_and_stop_bot(client):
    stop_resp = client.post("/api/v1/bots/apex_titan_btc/stop")
    assert stop_resp.status_code == 200
    assert stop_resp.json()["status"] == "STOPPED"

    bot_resp = client.get("/api/v1/bots/apex_titan_btc")
    assert bot_resp.json()["status"] == "STOPPED"

    start_resp = client.post("/api/v1/bots/apex_titan_btc/start")
    assert start_resp.status_code == 200
    assert start_resp.json()["status"] == "RUNNING"

    # Leave it stopped for safety
    client.post("/api/v1/bots/apex_titan_btc/stop")


def test_metrics_overview(client):
    response = client.get("/api/v1/metrics/overview")
    assert response.status_code == 200
    data = response.json()
    assert "total_portfolio_equity_usdt" in data
    assert "total_cash_flow_extracted_usdt" in data
    assert "active_bots_count" in data


def test_metrics_history(client):
    response = client.get("/api/v1/metrics/history")
    assert response.status_code == 200
    points = response.json()
    assert isinstance(points, list)
    assert len(points) >= 1
    assert "equity" in points[0]
    assert "cash_flow" in points[0]


def test_websocket_live_channel(client):
    with client.websocket_connect("/ws/live") as ws:
        # Recibir mensaje de bienvenida
        welcome = ws.receive_json()
        assert welcome["event"] == "connected"

        # Probar ping-pong
        ws.send_text("ping")
        pong = ws.receive_json()
        assert pong["event"] == "pong"


def test_generate_test_bot(client):
    response = client.post("/api/v1/bots/test?dry_run=true&budget=150.0")
    assert response.status_code == 201
    bot = response.json()
    assert "test_bot_" in bot["bot_id"]
    assert bot["budget"] == 150.0
    assert bot["dry_run"] is True
    assert bot["strategy_name"] == "BtcQuantumEvolutionRegimeStrategy"


def test_get_and_patch_system_settings(client):
    response = client.get("/api/v1/system/settings")
    assert response.status_code == 200
    data = response.json()
    assert "discord" in data
    assert "telegram" in data
    assert data["discord"]["is_configured"] is True

    # Test patch dynamic update
    patch_resp = client.patch(
        "/api/v1/system/settings",
        json={
            "discord_enabled": True,
            "telegram_bot_token": "123456:ABC-DEF1234ghIkl-zyx57W2v1u123ew11",
            "telegram_chat_id": "987654321",
            "telegram_enabled": False,
        },
    )
    assert patch_resp.status_code == 200
    updated = patch_resp.json()
    assert updated["discord"]["enabled"] is True
    assert updated["telegram"]["is_configured"] is True
    assert updated["telegram"]["enabled"] is False


def test_post_notification_test(client):
    from unittest.mock import AsyncMock, patch

    with patch("src.core.discord_notifier.DiscordNotifier.send_test_message", new_callable=AsyncMock) as mock_send:
        mock_send.return_value = True
        resp = client.post("/api/v1/system/notifications/test", json={"channel": "discord"})
        assert resp.status_code == 200
        res = resp.json()
        assert res["status"] == "success"
        assert res["channel"] == "discord"


def test_create_live_bot_without_credentials_rejected(client):
    """Verifies that creating a live trading bot without credentials is rejected with HTTP 400."""
    payload = {
        "bot_id": "live_unauthorized_bot",
        "symbol": "BTC/USDT",
        "budget": 1000.0,
        "dry_run": False,  # Real money!
        "strategy_name": "BtcQuantumEvolutionRegimeStrategy",
    }
    resp = client.post("/api/v1/bots", json=payload)
    assert resp.status_code == 400
    assert "ZERO-TRUST" in resp.json()["detail"]


def test_start_live_bot_without_credentials_rejected(client):
    """Verifies that starting a live bot lacking subaccount credentials fails loudly."""
    from src.api.services.bot_service import BotService
    service = BotService.get_instance()
    bot = service.bots["apex_titan_btc"]
    original_dry_run = bot.dry_run
    try:
        # Simulate bot configured in live mode without credentials
        bot.dry_run = False
        bot.config.api_key = None
        bot.config.api_secret = None
        bot.config.api_passphrase = None

        resp = client.post("/api/v1/bots/apex_titan_btc/start")
        assert resp.status_code == 400
        assert "ZERO-TRUST" in resp.json()["detail"]
    finally:
        bot.dry_run = original_dry_run


def test_create_live_bot_with_valid_credentials_accepted(client):
    """Verifies that a live bot with dedicated subaccount credentials creates successfully."""
    payload = {
        "bot_id": "live_legit_subaccount_bot",
        "symbol": "ETH/USDT",
        "budget": 2000.0,
        "dry_run": False,
        "strategy_name": "BtcQuantumEvolutionRegimeStrategy",
        "subaccount_name": "LegitSubaccount1",
        "api_key": "sub_valid_api_key",
        "api_secret": "sub_valid_api_secret",
        "api_passphrase": "sub_valid_api_passphrase",
    }
    resp = client.post("/api/v1/bots", json=payload)
    assert resp.status_code == 201
    bot_data = resp.json()
    assert bot_data["bot_id"] == "live_legit_subaccount_bot"
    assert bot_data["dry_run"] is False
    assert bot_data["subaccount_name"] == "LegitSubaccount1"


