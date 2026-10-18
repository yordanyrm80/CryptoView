import os
import pytest
from src.domain.models import Candle, Tranche, TrancheStatus
from src.storage.candle_repository import CandleRepository
from src.storage.capital_repository import CapitalRepository
from src.storage.database import DatabaseManager, PostgresConnectionWrapper
from src.storage.tranche_repository import TrancheRepository


@pytest.fixture
def db_manager():
    return DatabaseManager()


def test_postgres_connection(db_manager):
    assert db_manager.dialect == "postgres"
    with db_manager.get_connection() as conn:
        assert isinstance(conn, PostgresConnectionWrapper)
        cur = conn.execute("SELECT 1 as test_val;")
        row = cur.fetchone()
        assert row["test_val"] == 1


def test_postgres_schema_tables_exist(db_manager):
    expected_tables = {"candles", "orders", "tranches", "capital_transactions", "bot_events"}
    query = """
        SELECT table_name 
        FROM information_schema.tables 
        WHERE table_schema = 'public';
    """
    with db_manager.get_connection() as conn:
        cur = conn.execute(query)
        tables = {row["table_name"] for row in cur.fetchall()}
        assert expected_tables.issubset(tables)


def test_postgres_tranche_repository_lifecycle(db_manager):
    repo = TrancheRepository(db_manager)
    test_tranche = Tranche(
        bot_id="pg_test_bot",
        symbol="BTC/USDT",
        tranche_index=999,
        allocated_budget=500.0,
        buy_price=60000.0,
        amount=0.008333,
        target_sell_price=61200.0,
        status=TrancheStatus.ACTIVE,
    )
    tranche_id = repo.save_tranche(test_tranche)
    assert tranche_id is not None
    assert test_tranche.id == tranche_id

    # Update tranche
    test_tranche.status = TrancheStatus.CLOSED
    test_tranche.actual_sell_price = 61250.0
    test_tranche.profit_usdt = 10.41
    updated = repo.update_tranche(test_tranche)
    assert updated is True

    # Cleanup test data
    with db_manager.get_connection() as conn:
        conn.execute("DELETE FROM tranches WHERE bot_id = %s;", ("pg_test_bot",))


def test_postgres_capital_repository_lifecycle(db_manager):
    repo = CapitalRepository(db_manager)
    tx_id = repo.record_transaction(
        bot_id="pg_test_bot",
        type="DEPOSIT",
        amount=1000.0,
        available_after=1000.0,
        reason="Test deposit in PostgreSQL",
    )
    assert tx_id > 0

    event_id = repo.record_event(
        bot_id="pg_test_bot",
        event_type="TEST_EVENT",
        details="Automated PostgreSQL test",
    )
    assert event_id > 0

    # Cleanup test data
    with db_manager.get_connection() as conn:
        conn.execute("DELETE FROM capital_transactions WHERE bot_id = %s;", ("pg_test_bot",))
        conn.execute("DELETE FROM bot_events WHERE bot_id = %s;", ("pg_test_bot",))
