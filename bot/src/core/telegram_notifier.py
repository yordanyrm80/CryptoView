import asyncio
import json
import logging
import os
from typing import Any, Optional
import urllib.request

logger = logging.getLogger("criptobot.telegram")


class TelegramNotifier:
    """Dispatches proactive alerts to a Telegram chat/channel.

    Supports dynamic database configuration with fallback to environment variables.
    Zero-dependency via urllib. Gracefully no-ops if credentials are not configured or disabled.
    """

    def __init__(
        self,
        bot_token: Optional[str] = None,
        chat_id: Optional[str] = None,
        settings_repo: Optional[Any] = None,
    ):
        self._explicit_bot_token = bot_token
        self._explicit_chat_id = chat_id
        self.settings_repo = settings_repo

    @property
    def bot_token(self) -> Optional[str]:
        """Resolves active Telegram bot token."""
        if self._explicit_bot_token:
            return self._explicit_bot_token
        if self.settings_repo is not None:
            try:
                cfg = self.settings_repo.get_telegram_config()
                if cfg.get("bot_token"):
                    return str(cfg["bot_token"]).strip()
            except Exception as e:
                logger.debug(f"Could not load telegram bot token from repo: {e}")
        env_val = os.getenv("TELEGRAM_BOT_TOKEN")
        return env_val.strip() if env_val else None

    @property
    def chat_id(self) -> Optional[str]:
        """Resolves active Telegram chat ID."""
        if self._explicit_chat_id:
            return self._explicit_chat_id
        if self.settings_repo is not None:
            try:
                cfg = self.settings_repo.get_telegram_config()
                if cfg.get("chat_id"):
                    return str(cfg["chat_id"]).strip()
            except Exception as e:
                logger.debug(f"Could not load telegram chat id from repo: {e}")
        env_val = os.getenv("TELEGRAM_CHAT_ID")
        return env_val.strip() if env_val else None

    @property
    def enabled(self) -> bool:
        """Determines if Telegram notifications are active and credentials provided."""
        token = self.bot_token
        chat = self.chat_id
        if not token or not chat:
            return False
        if self._explicit_bot_token and self._explicit_chat_id:
            return True
        if self.settings_repo is not None:
            try:
                cfg = self.settings_repo.get_telegram_config()
                if "enabled" in cfg:
                    return bool(cfg["enabled"])
            except Exception as e:
                logger.debug(f"Could not load telegram enabled flag from repo: {e}")
        return True

    def configure(self, bot_token: str, chat_id: str, enabled: bool = True) -> None:
        """Dynamically updates Telegram credentials in memory and PostgreSQL."""
        self._explicit_bot_token = bot_token.strip() if bot_token else None
        self._explicit_chat_id = chat_id.strip() if chat_id else None
        if self.settings_repo is not None:
            self.settings_repo.set_telegram_config(bot_token=bot_token, chat_id=chat_id, enabled=enabled)
            logger.info("TelegramNotifier configuration saved to database.")

    @staticmethod
    def mask_token(token: Optional[str]) -> str:
        """Masks bot token for safe API display."""
        if not token:
            return ""
        s = token.strip()
        if len(s) > 10:
            return s[:4] + "..." + s[-4:]
        return "******"

    async def send_message(self, text: str) -> bool:
        """Sends an HTML/Markdown formatted notification asynchronously."""
        if not self.enabled:
            return False

        token = self.bot_token
        chat = self.chat_id
        if not token or not chat:
            return False

        url = f"https://api.telegram.org/bot{token}/sendMessage"
        payload = {
            "chat_id": chat,
            "text": text,
            "parse_mode": "HTML",
        }

        try:
            loop = asyncio.get_running_loop()
            return await loop.run_in_executor(None, self._post_sync, url, payload)
        except Exception as e:
            logger.error(f"Error sending Telegram notification: {e}")
            return False

    def _post_sync(self, url: str, payload: dict) -> bool:
        data = json.dumps(payload).encode("utf-8")
        req = urllib.request.Request(
            url,
            data=data,
            headers={"Content-Type": "application/json", "User-Agent": "CriptoBot/1.0"},
        )
        try:
            with urllib.request.urlopen(req, timeout=5) as resp:
                return resp.status == 200
        except Exception as e:
            logger.warning(f"Telegram API request failed: {e}")
            return False

    async def notify_buy(
        self,
        bot_id: str,
        tranche_index: int,
        symbol: str,
        price: float,
        amount: float,
        allocated_usdt: float,
        target_tp: float,
        is_dry_run: bool = True,
    ):
        mode_str = "🟡 [SIMULACIÓN]" if is_dry_run else "🟢 [REAL MONEY]"
        msg = (
            f"<b>{mode_str} COMPRA EJECUTADA</b>\n"
            f"🤖 <b>Bot:</b> <code>{bot_id}</code>\n"
            f"📊 <b>Par:</b> {symbol}\n"
            f"🎯 <b>Tramo:</b> T{tranche_index}\n"
            f"💵 <b>Precio:</b> ${price:,.2f}\n"
            f"🪙 <b>Cantidad:</b> {amount:.6f} {symbol.split('/')[0]}\n"
            f"💰 <b>Asignado:</b> ${allocated_usdt:.2f} USDT\n"
            f"🎯 <b>Take Profit:</b> ${target_tp:,.2f} (+{((target_tp/price)-1)*100:.2f}%)"
        )
        await self.send_message(msg)

    async def notify_sell(
        self,
        bot_id: str,
        tranche_index: int,
        symbol: str,
        sell_price: float,
        profit_usdt: float,
        is_dry_run: bool = True,
    ):
        mode_str = "🟡 [SIMULACIÓN]" if is_dry_run else "💰 [REAL MONEY]"
        profit_sign = "+" if profit_usdt >= 0 else ""
        msg = (
            f"<b>{mode_str} TRAMO VENDIDO CON BENEFICIO</b>\n"
            f"🤖 <b>Bot:</b> <code>{bot_id}</code>\n"
            f"📊 <b>Par:</b> {symbol}\n"
            f"🎯 <b>Tramo:</b> T{tranche_index}\n"
            f"💵 <b>Precio Venta:</b> ${sell_price:,.2f}\n"
            f"🎉 <b>Beneficio Neto:</b> <b>{profit_sign}${profit_usdt:.2f} USDT</b>"
        )
        await self.send_message(msg)

    async def notify_bot_status(self, bot_id: str, status: str, details: str = ""):
        msg = (
            f"ℹ️ <b>ESTADO DE BOT ACTUALIZADO</b>\n"
            f"🤖 <b>Bot:</b> <code>{bot_id}</code>\n"
            f"⚡ <b>Nuevo Estado:</b> <b>{status}</b>\n"
            f"📝 <b>Detalle:</b> {details}"
        )
        await self.send_message(msg)
