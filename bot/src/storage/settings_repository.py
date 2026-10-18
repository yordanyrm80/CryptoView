import json
import logging
import time
from typing import Any, Dict, Optional
from src.storage.database import DatabaseManager

logger = logging.getLogger(__name__)


class SettingsRepository:
    """Manages persistent dynamic system configurations stored in PostgreSQL."""

    def __init__(self, db_manager: DatabaseManager):
        self.db = db_manager

    def get_setting(self, key: str, default: Any = None) -> Any:
        """Retrieves a configuration value by key."""
        query = "SELECT value_json FROM system_settings WHERE key = %s;"
        try:
            with self.db.get_connection() as conn:
                cur = conn.execute(query, (key,))
                row = cur.fetchone()
                if row and row["value_json"]:
                    return json.loads(row["value_json"])
        except Exception as e:
            logger.error(f"Error fetching system setting '{key}': {e}")
        return default

    def set_setting(self, key: str, value: Any) -> None:
        """Upserts a configuration value by key."""
        now = int(time.time())
        val_json = json.dumps(value)
        query = """
            INSERT INTO system_settings (key, value_json, updated_at)
            VALUES (%s, %s, %s)
            ON CONFLICT (key) DO UPDATE 
            SET value_json = EXCLUDED.value_json, updated_at = EXCLUDED.updated_at;
        """
        try:
            with self.db.get_connection() as conn:
                conn.execute(query, (key, val_json, now))
        except Exception as e:
            logger.error(f"Error saving system setting '{key}': {e}")
            raise

    def get_all_settings(self) -> Dict[str, Any]:
        """Returns all configured system settings."""
        query = "SELECT key, value_json FROM system_settings;"
        results = {}
        try:
            with self.db.get_connection() as conn:
                cur = conn.execute(query)
                for row in cur.fetchall():
                    try:
                        results[row["key"]] = json.loads(row["value_json"])
                    except Exception:
                        results[row["key"]] = row["value_json"]
        except Exception as e:
            logger.error(f"Error fetching all system settings: {e}")
        return results

    def get_discord_config(self) -> Dict[str, Any]:
        """Returns Discord configuration with default structure."""
        return self.get_setting("discord", {"webhook_url": "", "enabled": False})

    def set_discord_config(self, webhook_url: str, enabled: bool = True) -> None:
        """Saves Discord webhook configuration."""
        self.set_setting("discord", {"webhook_url": webhook_url.strip(), "enabled": enabled})

    def get_telegram_config(self) -> Dict[str, Any]:
        """Returns Telegram configuration with default structure."""
        return self.get_setting("telegram", {"bot_token": "", "chat_id": "", "enabled": False})

    def set_telegram_config(self, bot_token: str, chat_id: str, enabled: bool = True) -> None:
        """Saves Telegram bot configuration."""
        self.set_setting("telegram", {"bot_token": bot_token.strip(), "chat_id": chat_id.strip(), "enabled": enabled})
