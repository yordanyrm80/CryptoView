from typing import List, Optional
from src.domain.models import Tranche, TrancheStatus
from src.storage.database import DatabaseManager


class TrancheRepository:
    """Repository for storing and managing operational tranches in PostgreSQL."""

    def __init__(self, db_manager: DatabaseManager):
        self.db_manager = db_manager

    def save_tranche(self, tranche: Tranche) -> int:
        """Inserts a new tranche into database and assigns its generated ID."""
        query = """
            INSERT INTO tranches (
                bot_id, symbol, tranche_index, allocated_budget, buy_price,
                amount, target_sell_price, actual_sell_price, status,
                buy_fee, sell_fee, buy_timestamp, sell_timestamp, profit_usdt
            ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
            RETURNING id;
        """
        values = (
            tranche.bot_id,
            tranche.symbol,
            tranche.tranche_index,
            tranche.allocated_budget,
            tranche.buy_price,
            tranche.amount,
            tranche.target_sell_price,
            tranche.actual_sell_price,
            tranche.status.value if hasattr(tranche.status, "value") else str(tranche.status),
            tranche.buy_fee,
            tranche.sell_fee,
            tranche.buy_timestamp,
            tranche.sell_timestamp,
            tranche.profit_usdt,
        )

        with self.db_manager.get_connection() as conn:
            cursor = conn.cursor()
            cursor.execute(query, values)
            row = cursor.fetchone()
            conn.commit()
            tranche.id = row["id"] if row else None
            return tranche.id

    def update_tranche(self, tranche: Tranche) -> bool:
        """Updates status, prices and profit of an existing tranche."""
        if tranche.id is None:
            query = """
                UPDATE tranches SET
                    target_sell_price = %s,
                    actual_sell_price = %s,
                    status = %s,
                    sell_fee = %s,
                    sell_timestamp = %s,
                    profit_usdt = %s
                WHERE bot_id = %s AND symbol = %s AND tranche_index = %s AND status = %s;
            """
            values = (
                tranche.target_sell_price,
                tranche.actual_sell_price,
                tranche.status.value if hasattr(tranche.status, "value") else str(tranche.status),
                tranche.sell_fee,
                tranche.sell_timestamp,
                tranche.profit_usdt,
                tranche.bot_id,
                tranche.symbol,
                tranche.tranche_index,
                TrancheStatus.ACTIVE.value,
            )
        else:
            query = """
                UPDATE tranches SET
                    target_sell_price = %s,
                    actual_sell_price = %s,
                    status = %s,
                    sell_fee = %s,
                    sell_timestamp = %s,
                    profit_usdt = %s
                WHERE id = %s;
            """
            values = (
                tranche.target_sell_price,
                tranche.actual_sell_price,
                tranche.status.value if hasattr(tranche.status, "value") else str(tranche.status),
                tranche.sell_fee,
                tranche.sell_timestamp,
                tranche.profit_usdt,
                tranche.id,
            )

        with self.db_manager.get_connection() as conn:
            cursor = conn.cursor()
            cursor.execute(query, values)
            conn.commit()
            return cursor.rowcount > 0

    def _row_to_tranche(self, row) -> Tranche:
        return Tranche(
            id=row["id"],
            bot_id=row["bot_id"],
            symbol=row["symbol"],
            tranche_index=row["tranche_index"],
            allocated_budget=row["allocated_budget"],
            buy_price=row["buy_price"],
            amount=row["amount"],
            target_sell_price=row["target_sell_price"],
            actual_sell_price=row["actual_sell_price"],
            status=TrancheStatus(row["status"]),
            buy_fee=row["buy_fee"],
            sell_fee=row["sell_fee"],
            buy_timestamp=row["buy_timestamp"],
            sell_timestamp=row["sell_timestamp"],
            profit_usdt=row["profit_usdt"],
        )

    def get_active_tranches(self, bot_id: str) -> List[Tranche]:
        """Gets all currently active tranches for a bot."""
        query = "SELECT * FROM tranches WHERE bot_id = %s AND status = %s ORDER BY tranche_index ASC;"
        with self.db_manager.get_connection() as conn:
            rows = conn.execute(query, [bot_id, TrancheStatus.ACTIVE.value]).fetchall()
            return [self._row_to_tranche(r) for r in rows]

    def get_completed_tranches(self, bot_id: str) -> List[Tranche]:
        """Gets completed/closed tranches for a bot."""
        query = "SELECT * FROM tranches WHERE bot_id = %s AND status = %s ORDER BY sell_timestamp ASC;"
        with self.db_manager.get_connection() as conn:
            rows = conn.execute(query, [bot_id, TrancheStatus.CLOSED.value]).fetchall()
            return [self._row_to_tranche(r) for r in rows]

    def get_all_tranches(self, bot_id: Optional[str] = None) -> List[Tranche]:
        """Gets all recorded tranches, optionally filtered by bot."""
        if bot_id:
            query = "SELECT * FROM tranches WHERE bot_id = %s ORDER BY id ASC;"
            params = [bot_id]
        else:
            query = "SELECT * FROM tranches ORDER BY id ASC;"
            params = []

        with self.db_manager.get_connection() as conn:
            rows = conn.execute(query, params).fetchall()
            return [self._row_to_tranche(r) for r in rows]

    def calculate_realized_profit(self, bot_id: str) -> float:
        """Calculates total net profit extracted from closed tranches."""
        query = "SELECT SUM(profit_usdt) as total_profit FROM tranches WHERE bot_id = %s AND status = %s;"
        with self.db_manager.get_connection() as conn:
            row = conn.execute(query, [bot_id, TrancheStatus.CLOSED.value]).fetchone()
            return float(row["total_profit"]) if row and row["total_profit"] is not None else 0.0
