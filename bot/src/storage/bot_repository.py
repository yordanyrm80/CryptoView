import json
import time
from typing import Any, Dict, List, Optional
from src.domain.models import BotConfig
from src.storage.database import DatabaseManager


class BotRecord:
    """Database representation of a deployed trading bot."""

    def __init__(
        self,
        bot_id: str,
        symbol: str,
        strategy_name: str,
        budget: float,
        status: str,
        dry_run: bool,
        config: BotConfig,
        created_at: int,
        updated_at: int,
    ):
        self.bot_id = bot_id
        self.symbol = symbol
        self.strategy_name = strategy_name
        self.budget = budget
        self.status = status
        self.dry_run = dry_run
        self.config = config
        self.created_at = created_at
        self.updated_at = updated_at


class BotRepository:
    """Repository for managing bot configurations and lifecycle states in PostgreSQL."""

    def __init__(self, db_manager: DatabaseManager):
        self.db_manager = db_manager

    def save_bot(
        self,
        bot_id: str,
        symbol: str,
        strategy_name: str,
        budget: float,
        status: str,
        dry_run: bool,
        config: BotConfig,
        created_at: Optional[int] = None,
        updated_at: Optional[int] = None,
    ) -> None:
        """Inserts or updates a bot configuration in PostgreSQL."""
        now = int(time.time() * 1000)
        c_at = created_at or now
        u_at = updated_at or now
        config_json = json.dumps(config.model_dump())

        query = """
            INSERT INTO bots (
                bot_id, symbol, strategy_name, budget, status, dry_run,
                config_json, created_at, updated_at
            ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)
            ON CONFLICT (bot_id) DO UPDATE SET
                status = EXCLUDED.status,
                budget = EXCLUDED.budget,
                dry_run = EXCLUDED.dry_run,
                config_json = EXCLUDED.config_json,
                updated_at = EXCLUDED.updated_at;
        """
        with self.db_manager.get_connection() as conn:
            conn.execute(
                query,
                (bot_id, symbol, strategy_name, budget, status, dry_run, config_json, c_at, u_at),
            )

    def update_status(self, bot_id: str, status: str) -> bool:
        """Updates the operational status of a bot (e.g. RUNNING, PAUSED, STOPPED)."""
        now = int(time.time() * 1000)
        query = """
            UPDATE bots 
            SET status = %s, updated_at = %s
            WHERE bot_id = %s;
        """
        with self.db_manager.get_connection() as conn:
            cur = conn.execute(query, (status, now, bot_id))
            return cur.rowcount > 0

    def get_bot(self, bot_id: str) -> Optional[BotRecord]:
        """Retrieves a single bot record by ID."""
        query = "SELECT * FROM bots WHERE bot_id = %s;"
        with self.db_manager.get_connection() as conn:
            row = conn.execute(query, (bot_id,)).fetchone()
            if not row:
                return None
            return self._row_to_record(row)

    def get_all_bots(self) -> List[BotRecord]:
        """Retrieves all registered bots from database."""
        query = "SELECT * FROM bots ORDER BY created_at ASC;"
        with self.db_manager.get_connection() as conn:
            rows = conn.execute(query).fetchall()
            return [self._row_to_record(r) for r in rows]

    def delete_bot(self, bot_id: str) -> bool:
        """Deletes a bot record by ID."""
        query = "DELETE FROM bots WHERE bot_id = %s;"
        with self.db_manager.get_connection() as conn:
            cur = conn.execute(query, (bot_id,))
            return cur.rowcount > 0

    def _row_to_record(self, row) -> BotRecord:
        raw_json = row["config_json"]
        parsed = json.loads(raw_json) if isinstance(raw_json, str) else raw_json
        config = BotConfig(**parsed)
        return BotRecord(
            bot_id=row["bot_id"],
            symbol=row["symbol"],
            strategy_name=row["strategy_name"],
            budget=row["budget"],
            status=row["status"],
            dry_run=bool(row["dry_run"]),
            config=config,
            created_at=row["created_at"],
            updated_at=row["updated_at"],
        )
