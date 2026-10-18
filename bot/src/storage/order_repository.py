import time
from typing import Any, Dict, List, Optional
from src.domain.models import Order
from src.storage.database import DatabaseManager


class OrderRepository:
    """Repository for storing and querying resting limit orders in PostgreSQL."""

    def __init__(self, db_manager: DatabaseManager):
        self.db_manager = db_manager

    def save_order(self, order: Order) -> None:
        """Inserts or updates an order in PostgreSQL."""
        query = """
            INSERT INTO orders (
                id, bot_id, symbol, side, order_type, price, amount,
                status, fee, created_at, filled_at
            ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
            ON CONFLICT (id) DO UPDATE SET
                status = EXCLUDED.status,
                fee = EXCLUDED.fee,
                filled_at = EXCLUDED.filled_at;
        """
        side_str = order.side.value if hasattr(order.side, "value") else str(order.side)
        type_str = order.order_type.value if hasattr(order.order_type, "value") else str(order.order_type)
        status_str = order.status.value if hasattr(order.status, "value") else str(order.status)

        with self.db_manager.get_connection() as conn:
            conn.execute(
                query,
                (
                    order.id,
                    order.bot_id,
                    order.symbol,
                    side_str,
                    type_str,
                    order.price,
                    order.amount,
                    status_str,
                    order.fee,
                    order.created_at,
                    order.filled_at,
                ),
            )

    def update_order_status(self, order_id: str, status: str, filled_at: Optional[int] = None, fee: float = 0.0) -> bool:
        """Updates the status and fill details of an order."""
        now = filled_at or int(time.time() * 1000)
        query = """
            UPDATE orders
            SET status = %s, filled_at = %s, fee = %s
            WHERE id = %s;
        """
        with self.db_manager.get_connection() as conn:
            cur = conn.execute(query, (status, now, fee, order_id))
            return cur.rowcount > 0

    def get_open_orders(self, bot_id: Optional[str] = None) -> List[Dict[str, Any]]:
        """Retrieves active/open resting orders from PostgreSQL."""
        if bot_id:
            query = "SELECT * FROM orders WHERE bot_id = %s AND status IN ('OPEN', 'NEW', 'SUBMITTED') ORDER BY created_at ASC;"
            params = (bot_id,)
        else:
            query = "SELECT * FROM orders WHERE status IN ('OPEN', 'NEW', 'SUBMITTED') ORDER BY created_at ASC;"
            params = ()

        with self.db_manager.get_connection() as conn:
            rows = conn.execute(query, params).fetchall()
            return [dict(r) for r in rows]

    def get_order(self, order_id: str) -> Optional[Dict[str, Any]]:
        """Retrieves a single order by ID."""
        query = "SELECT * FROM orders WHERE id = %s;"
        with self.db_manager.get_connection() as conn:
            row = conn.execute(query, (order_id,)).fetchone()
            return dict(row) if row else None
