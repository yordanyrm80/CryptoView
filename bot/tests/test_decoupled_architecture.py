import asyncio
import pytest
from src.core.event_bus import DomainEvent, EventBus
from src.core.ingestor import MarketDataIngestor
from src.domain.models import BotConfig, BotInstance, Order, OrderSide, OrderStatus, OrderType, TrancheStatus
from src.storage.bot_repository import BotRepository
from src.storage.database import DatabaseManager
from src.storage.order_repository import OrderRepository
from src.core.live_runner import LiveRunner
from src.api.services.bot_service import BotService


@pytest.fixture
def db_mgr():
    return DatabaseManager()


@pytest.mark.anyio
async def test_event_bus_pub_sub_isolation():
    bus = EventBus()
    received_events = []

    async def sample_handler(event: DomainEvent):
        received_events.append(event)

    async def faulty_handler(event: DomainEvent):
        raise RuntimeError("Simulated consumer failure")

    bus.subscribe("TEST_EVENT", sample_handler)
    bus.subscribe("TEST_EVENT", faulty_handler)

    test_ev = DomainEvent(event_type="TEST_EVENT", bot_id="bot_1", data={"price": 65000.0})
    bus.publish(test_ev)

    await asyncio.sleep(0.05)
    assert len(received_events) == 1
    assert received_events[0].bot_id == "bot_1"
    assert received_events[0].data["price"] == 65000.0


def test_bot_repository_persistence(db_mgr):
    repo = BotRepository(db_mgr)
    cfg = BotConfig(
        bot_id="persist_test_bot",
        symbol="BTC/USDT",
        budget=750.0,
        take_profit_pct=4.8,
    )
    repo.save_bot(
        bot_id=cfg.bot_id,
        symbol=cfg.symbol,
        strategy_name="BtcQuantumEvolutionRegimeStrategy",
        budget=cfg.budget,
        status="PAUSED",
        dry_run=True,
        config=cfg,
    )

    bot_record = repo.get_bot("persist_test_bot")
    assert bot_record is not None
    assert bot_record.bot_id == "persist_test_bot"
    assert bot_record.status == "PAUSED"
    assert bot_record.budget == 750.0
    assert bot_record.config.take_profit_pct == 4.8

    # Update status to RUNNING
    updated = repo.update_status("persist_test_bot", "RUNNING")
    assert updated is True
    reloaded = repo.get_bot("persist_test_bot")
    assert reloaded.status == "RUNNING"

    # Cleanup
    with db_mgr.get_connection() as conn:
        conn.execute("DELETE FROM bots WHERE bot_id = %s;", ("persist_test_bot",))


def test_order_repository_lifecycle(db_mgr):
    repo = OrderRepository(db_mgr)
    order = Order(
        id="test_ord_101",
        bot_id="order_test_bot",
        symbol="BTC/USDT",
        side=OrderSide.BUY,
        order_type=OrderType.LIMIT,
        price=61000.0,
        amount=0.01,
        status=OrderStatus.OPEN,
        created_at=1700000000,
    )
    repo.save_order(order)

    fetched = repo.get_order("test_ord_101")
    assert fetched is not None
    assert fetched["status"] == "OPEN"
    assert fetched["price"] == 61000.0

    open_orders = repo.get_open_orders(bot_id="order_test_bot")
    assert any(o["id"] == "test_ord_101" for o in open_orders)

    # Transition to CLOSED upon fill
    repo.update_order_status("test_ord_101", "CLOSED", filled_at=1700003600, fee=0.61)
    closed_ord = repo.get_order("test_ord_101")
    assert closed_ord["status"] == "CLOSED"
    assert closed_ord["fee"] == 0.61

    # Cleanup
    with db_mgr.get_connection() as conn:
        conn.execute("DELETE FROM orders WHERE bot_id = %s;", ("order_test_bot",))


@pytest.mark.anyio
async def test_live_runner_limit_order_workflow(db_mgr):
    service = BotService.get_instance()
    runner = LiveRunner(bot_service=service, db_manager=db_mgr)

    bot_id = "apex_titan_btc"
    bot = service.bots[bot_id]

    # Run cycle against PostgreSQL historical data
    await runner.run_cycle()

    # Verify orders table can be queried and no unhandled crashes occur
    open_orders = runner.order_repo.get_open_orders(bot_id=bot_id)
    assert isinstance(open_orders, list)


@pytest.mark.anyio
async def test_discord_notifier_disabled_by_default(monkeypatch):
    from src.core.discord_notifier import DiscordNotifier

    monkeypatch.delenv("DISCORD_WEBHOOK_URL", raising=False)
    notifier = DiscordNotifier(webhook_url=None)
    assert notifier.enabled is False
    res = await notifier.send_embed(title="Test")
    assert res is False


@pytest.mark.anyio
async def test_discord_notifier_embed_dispatch():
    from unittest.mock import AsyncMock, patch, MagicMock
    from src.core.discord_notifier import DiscordNotifier

    mock_resp = MagicMock()
    mock_resp.status_code = 204

    with patch("httpx.AsyncClient.post", new_callable=AsyncMock) as mock_post:
        mock_post.return_value = mock_resp
        notifier = DiscordNotifier(webhook_url="https://discord.com/api/webhooks/123/fake_token")
        assert notifier.enabled is True

        # Test buy alert
        ok = await notifier.notify_buy(
            bot_id="test_bot",
            tranche_index=1,
            symbol="BTC/USDT",
            price=60000.0,
            amount=0.005,
            allocated_usdt=300.0,
            target_tp=63000.0,
            is_dry_run=False,
        )
        assert ok is True
        assert mock_post.called
        call_kwargs = mock_post.call_args[1]
        payload = call_kwargs["json"]
        assert len(payload["embeds"]) == 1
        assert "BUY" in payload["embeds"][0]["title"]
        assert payload["embeds"][0]["color"] == 0x00E676

        # Test sell alert
        ok_sell = await notifier.notify_sell(
            bot_id="test_bot",
            tranche_index=1,
            symbol="BTC/USDT",
            sell_price=63000.0,
            profit_usdt=15.0,
            is_dry_run=False,
        )
        assert ok_sell is True
        payload_sell = mock_post.call_args[1]["json"]
        assert "TAKE PROFIT" in payload_sell["embeds"][0]["title"]
        assert payload_sell["embeds"][0]["color"] == 0xFFD700


@pytest.mark.anyio
async def test_notification_dispatcher_dispatches_to_discord():
    from unittest.mock import AsyncMock
    from src.core.notification_dispatcher import NotificationDispatcher
    from src.core.discord_notifier import DiscordNotifier

    mock_discord = AsyncMock(spec=DiscordNotifier)
    mock_discord.enabled = True

    bus = EventBus()
    dispatcher = NotificationDispatcher(event_bus=bus, discord_notifier=mock_discord)
    dispatcher.start()

    ev = DomainEvent(
        event_type="TRANCHE_BOUGHT",
        bot_id="bot_disco",
        data={
            "tranche_index": 2,
            "symbol": "BTC/USDT",
            "buy_price": 62000.0,
            "amount": 0.003,
            "allocated_budget": 186.0,
            "target_sell_price": 65000.0,
            "is_dry_run": False,
        },
    )
    bus.publish(ev)

    await asyncio.sleep(0.1)
    dispatcher.stop()

    assert mock_discord.notify_buy.called
    call_kwargs = mock_discord.notify_buy.call_args.kwargs
    assert call_kwargs["bot_id"] == "bot_disco"
    assert call_kwargs["tranche_index"] == 2
    assert call_kwargs["price"] == 62000.0


def test_subaccount_client_isolation(monkeypatch):
    """Verifies that multiple bots with distinct subaccount credentials get isolated KuCoin clients."""
    from src.domain.models import BotInstance

    cfg_sub1 = BotConfig(
        bot_id="bot_subaccount_alpha",
        symbol="BTC/USDT",
        budget=1000.0,
        take_profit_pct=4.5,
        subaccount_name="TradingAlpha",
        api_key="key_alpha",
        api_secret="secret_alpha",
        api_passphrase="pass_alpha",
    )
    bot1 = BotInstance(config=cfg_sub1, strategy_name="BtcQuantumEvolutionRegimeStrategy", dry_run=False)

    cfg_sub2 = BotConfig(
        bot_id="bot_subaccount_beta",
        symbol="ETH/USDT",
        budget=2000.0,
        take_profit_pct=5.0,
        subaccount_name="TradingBeta",
        api_key="key_beta",
        api_secret="secret_beta",
        api_passphrase="pass_beta",
    )
    bot2 = BotInstance(config=cfg_sub2, strategy_name="BtcQuantumEvolutionRegimeStrategy", dry_run=False)

    cfg_default = BotConfig(
        bot_id="bot_no_subaccount",
        symbol="SOL/USDT",
        budget=500.0,
        take_profit_pct=3.5,
    )
    bot_live_no_creds = BotInstance(config=cfg_default, strategy_name="BtcQuantumEvolutionRegimeStrategy", dry_run=False)
    bot_dry_run = BotInstance(config=cfg_default, strategy_name="BtcQuantumEvolutionRegimeStrategy", dry_run=True)

    from unittest.mock import MagicMock
    mock_default_client = MagicMock()
    runner = LiveRunner(kucoin_client=mock_default_client)

    client1 = runner.get_exchange_client(bot1)
    client2 = runner.get_exchange_client(bot2)

    assert client1 is not None
    assert client2 is not None
    assert client1 is not client2
    assert client1.api_key == "key_alpha"
    assert client2.api_key == "key_beta"

    # Zero-Trust Verification: Live bots without credentials MUST raise ValueError (NO FALLBACK!)
    import pytest
    with pytest.raises(ValueError, match="CRITICAL ZERO-TRUST SECURITY VIOLATION"):
        runner.get_exchange_client(bot_live_no_creds)

    # Dry-run bots do not touch private exchange endpoints and return None
    assert runner.get_exchange_client(bot_dry_run) is None


@pytest.mark.anyio
async def test_run_cycle_security_halt_for_live_bot_without_credentials():
    """Verifies that if a bot is running live without credentials, run_cycle halts it immediately to STOPPED."""
    cfg = BotConfig(
        bot_id="unauthorized_live_runner_bot",
        symbol="BTC/USDT",
        budget=1000.0,
        take_profit_pct=4.0,
    )
    bot = BotInstance(config=cfg, strategy_name="BtcQuantumEvolutionRegimeStrategy", dry_run=False)
    bot.status = "RUNNING"

    runner = LiveRunner(bots={"unauthorized_live_runner_bot": bot})
    await runner.run_cycle()

    # The bot must be automatically halted to STOPPED due to security violation
    assert bot.status == "STOPPED"


