import time
from typing import List, Optional, Tuple
from src.domain.models import BotEvent, CapitalTransaction
from src.storage.database import DatabaseManager


class CapitalRepository:
    """Repository for storing capital transactions and bot lifecycle audit events in PostgreSQL."""

    def __init__(self, db_manager: DatabaseManager):
        self.db_manager = db_manager

    def record_transaction(
        self,
        bot_id: str,
        type: str,
        amount: float,
        available_after: float,
        timestamp: Optional[int] = None,
        reason: Optional[str] = None,
    ) -> int:
        ts = timestamp or int(time.time() * 1000)
        query = """
            INSERT INTO capital_transactions 
            (bot_id, type, amount, available_after, timestamp, reason)
            VALUES (%s, %s, %s, %s, %s, %s)
            RETURNING id;
        """
        with self.db_manager.get_connection() as conn:
            cursor = conn.cursor()
            cursor.execute(query, (bot_id, type, amount, available_after, ts, reason))
            row = cursor.fetchone()
            conn.commit()
            return row["id"] if row else 0

    def get_totals(self, bot_id: str) -> Tuple[float, float]:
        """Calculates (total_deposited, total_withdrawn) for a bot."""
        query = """
            SELECT type, SUM(amount) as total
            FROM capital_transactions
            WHERE bot_id = %s
            GROUP BY type;
        """
        total_deposited = 0.0
        total_withdrawn = 0.0
        with self.db_manager.get_connection() as conn:
            cursor = conn.cursor()
            cursor.execute(query, (bot_id,))
            for row in cursor.fetchall():
                if row["type"] == "DEPOSIT":
                    total_deposited = float(row["total"] or 0.0)
                elif row["type"] == "WITHDRAWAL":
                    total_withdrawn = float(row["total"] or 0.0)
        return total_deposited, total_withdrawn

    def get_transactions(self, bot_id: str) -> List[CapitalTransaction]:
        """Gets all capital transactions ordered chronologically."""
        query = """
            SELECT id, bot_id, type, amount, available_after, timestamp, reason
            FROM capital_transactions
            WHERE bot_id = %s
            ORDER BY timestamp ASC;
        """
        with self.db_manager.get_connection() as conn:
            cursor = conn.cursor()
            cursor.execute(query, (bot_id,))
            return [
                CapitalTransaction(
                    id=row["id"],
                    bot_id=row["bot_id"],
                    type=row["type"],
                    amount=row["amount"],
                    available_after=row["available_after"],
                    timestamp=row["timestamp"],
                    reason=row["reason"],
                )
                for row in cursor.fetchall()
            ]

    def record_event(
        self,
        bot_id: str,
        event_type: str,
        details: Optional[str] = None,
        timestamp: Optional[int] = None,
    ) -> int:
        """Records a bot lifecycle audit event."""
        ts = timestamp or int(time.time() * 1000)
        query = """
            INSERT INTO bot_events (bot_id, event_type, details, timestamp)
            VALUES (%s, %s, %s, %s)
            RETURNING id;
        """
        with self.db_manager.get_connection() as conn:
            cursor = conn.cursor()
            cursor.execute(query, (bot_id, event_type, details, ts))
            row = cursor.fetchone()
            conn.commit()
            return row["id"] if row else 0

    def get_events(self, bot_id: str) -> List[BotEvent]:
        """Gets complete bot events log."""
        query = """
            SELECT id, bot_id, event_type, details, timestamp
            FROM bot_events
            WHERE bot_id = %s
            ORDER BY timestamp ASC;
        """
        with self.db_manager.get_connection() as conn:
            cursor = conn.cursor()
            cursor.execute(query, (bot_id,))
            return [
                BotEvent(
                    id=row["id"],
                    bot_id=row["bot_id"],
                    event_type=row["event_type"],
                    details=row["details"],
                    timestamp=row["timestamp"],
                )
                for row in cursor.fetchall()
            ]
