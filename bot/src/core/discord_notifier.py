import datetime
import logging
import os
from typing import Any, Dict, List, Optional
import httpx

logger = logging.getLogger("criptobot.discord")


class DiscordNotifier:
    """Dispatches proactive alerts to a Discord channel via Webhook.

    Supports dynamic database configuration with fallback to environment variables.
    Formats institutional-grade Rich Embeds with color-coding and structured fields.
    Gracefully no-ops if webhook is not configured or disabled.
    """

    def __init__(self, webhook_url: Optional[str] = None, settings_repo: Optional[Any] = None):
        self._explicit_webhook_url = webhook_url
        self.settings_repo = settings_repo

    @property
    def webhook_url(self) -> Optional[str]:
        """Resolves active webhook URL from explicit arg, database, or .env."""
        if self._explicit_webhook_url:
            return self._explicit_webhook_url
        if self.settings_repo is not None:
            try:
                cfg = self.settings_repo.get_discord_config()
                if cfg.get("webhook_url"):
                    return str(cfg["webhook_url"]).strip()
            except Exception as e:
                logger.debug(f"Could not load discord setting from repo: {e}")
        env_val = os.getenv("DISCORD_WEBHOOK_URL")
        return env_val.strip() if env_val else None

    @property
    def enabled(self) -> bool:
        """Determines if Discord dispatching is active and properly configured."""
        url = self.webhook_url
        if not url or not url.startswith("http"):
            return False
        if self._explicit_webhook_url:
            return True
        if self.settings_repo is not None:
            try:
                cfg = self.settings_repo.get_discord_config()
                if "enabled" in cfg:
                    return bool(cfg["enabled"])
            except Exception as e:
                logger.debug(f"Could not load discord enabled flag from repo: {e}")
        return True

    def configure(self, webhook_url: str, enabled: bool = True) -> None:
        """Dynamically reconfigures Discord webhook in memory and PostgreSQL."""
        self._explicit_webhook_url = webhook_url.strip() if webhook_url else None
        if self.settings_repo is not None:
            self.settings_repo.set_discord_config(webhook_url=webhook_url, enabled=enabled)
            logger.info("DiscordNotifier configuration saved to database.")

    @staticmethod
    def mask_webhook_url(url: Optional[str]) -> str:
        """Masks sensitive token part of webhook URL for safe UI/API rendering."""
        if not url:
            return ""
        parts = url.strip().split("/")
        if len(parts) >= 2:
            return "/".join(parts[:-1]) + "/******"
        return "******"

    async def send_embed(
        self,
        title: str,
        description: str = "",
        color: int = 0x3498DB,
        fields: Optional[List[Dict[str, Any]]] = None,
        footer_text: str = "Apex Quant Engine • KuCoin Spot",
    ) -> bool:
        """Sends a Discord Rich Embed asynchronously via HTTP POST."""
        if not self.enabled:
            return False

        url = self.webhook_url
        if not url:
            return False

        payload = {
            "username": "Apex Quant",
            "avatar_url": "https://raw.githubusercontent.com/feathericons/feather/master/icons/trending-up.svg",
            "embeds": [
                {
                    "title": title,
                    "description": description,
                    "color": color,
                    "fields": fields or [],
                    "footer": {"text": footer_text},
                    "timestamp": datetime.datetime.now(datetime.timezone.utc).isoformat(),
                }
            ],
        }

        try:
            async with httpx.AsyncClient(timeout=10.0) as client:
                resp = await client.post(url, json=payload)
                if resp.status_code in (200, 204):
                    return True
                logger.warning(f"Discord webhook failed with HTTP {resp.status_code}: {resp.text}")
                return False
        except Exception as e:
            logger.error(f"Error dispatching Discord webhook alert: {e}")
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
    ) -> bool:
        """Dispatches a compact emerald green buy execution embed."""
        mode_prefix = "🟡 [SIM] " if is_dry_run else "🟢 "
        color = 0x2ECC71 if is_dry_run else 0x00E676
        coin = symbol.split("/")[0] if "/" in symbol else "BTC"
        tp_pct = ((target_tp / price) - 1.0) * 100.0 if price > 0 else 0.0

        title = f"{mode_prefix}BUY T{tranche_index} • {symbol} @ ${price:,.2f}"
        fields = [
            {"name": "Volumen", "value": f"`{amount:.6f} {coin}` (${allocated_usdt:,.2f})", "inline": True},
            {"name": "Objetivo TP", "value": f"`${target_tp:,.2f}` (+{tp_pct:.2f}%)", "inline": True},
        ]
        footer = f"{bot_id} • Maker Limit"
        return await self.send_embed(title=title, color=color, fields=fields, footer_text=footer)

    async def notify_sell(
        self,
        bot_id: str,
        tranche_index: int,
        symbol: str,
        sell_price: float,
        profit_usdt: float,
        is_dry_run: bool = True,
    ) -> bool:
        """Dispatches a compact gold take profit execution embed."""
        mode_prefix = "🟡 [SIM] " if is_dry_run else "💰 "
        color = 0xFFD700
        profit_sign = "+" if profit_usdt >= 0 else ""

        title = f"{mode_prefix}TAKE PROFIT T{tranche_index} • {symbol} @ ${sell_price:,.2f}"
        fields = [
            {"name": "Beneficio Neto", "value": f"**{profit_sign}${profit_usdt:,.2f} USDT**", "inline": True},
            {"name": "Estado", "value": "Capital reciclado", "inline": True},
        ]
        footer = f"{bot_id} • Cash Flow Realizado"
        return await self.send_embed(title=title, color=color, fields=fields, footer_text=footer)

    async def notify_bot_status(self, bot_id: str, status: str, details: str = "") -> bool:
        """Dispatches a compact status change embed."""
        title = f"ℹ️ {bot_id} ➔ {status}"
        color = 0x3498DB
        desc = f"_{details}_" if details else ""
        return await self.send_embed(title=title, description=desc, color=color, fields=[])

    async def notify_capital_adjustment(self, bot_id: str, tx_type: str, amount: float, reason: str = "") -> bool:
        """Dispatches a compact capital adjustment embed."""
        title = f"💳 {bot_id}: {tx_type} ${amount:,.2f} USDT"
        color = 0x9B59B6
        desc = f"_{reason}_" if reason else ""
        return await self.send_embed(title=title, description=desc, color=color, fields=[])

    async def notify_alert(self, title: str, message: str, severity: str = "WARNING") -> bool:
        """Dispatches a compact system health or operational warning embed."""
        color = 0xE74C3C if severity.upper() == "CRITICAL" else 0xE67E22
        alert_title = f"🚨 [{severity.upper()}] {title}"
        return await self.send_embed(title=alert_title, description=message, color=color, fields=[])

    async def send_test_message(self) -> bool:
        """Sends a compact diagnostic test message to verify mobile alert connectivity."""
        return await self.send_embed(
            title="🔔 APEX QUANT • Conexión Activa",
            description="Diagnóstico OK • Notificaciones prioritarias operativas en tu dispositivo.",
            color=0x00E676,
            fields=[],
            footer_text="Apex Quant Engine • Test OK",
        )

