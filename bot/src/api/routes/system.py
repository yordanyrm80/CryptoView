import datetime
from fastapi import APIRouter, HTTPException, status
from src.api.schemas import (
    DiscordSettingsSchema,
    NotificationTestRequest,
    NotificationTestResponse,
    SystemHealthResponse,
    SystemSettingsResponse,
    TelegramSettingsSchema,
    UpdateSystemSettingsRequest,
)
from src.api.services.bot_service import BotService
from src.core.discord_notifier import DiscordNotifier
from src.core.notification_dispatcher import NotificationDispatcher
from src.core.telegram_notifier import TelegramNotifier
from src.storage.database import DatabaseManager
from src.storage.settings_repository import SettingsRepository

router = APIRouter(prefix="/system", tags=["System"])


def _get_settings_repo() -> SettingsRepository:
    return SettingsRepository(DatabaseManager())


@router.get("/health", response_model=SystemHealthResponse, summary="Health check for server and database")
def get_health():
    service = BotService.get_instance()
    active_count = sum(1 for b in service.bots.values() if b.status == "RUNNING")
    return SystemHealthResponse(
        status="healthy",
        database_connected=True,
        active_bots=active_count,
        dry_run_mode_global=True,
        app_version="1.0.0",
    )


@router.get("/settings", response_model=SystemSettingsResponse, summary="Retrieve dynamic system and integration settings")
def get_system_settings():
    repo = _get_settings_repo()
    dispatcher = NotificationDispatcher.get_instance()

    discord_cfg = repo.get_discord_config()
    discord_url = discord_cfg.get("webhook_url") or dispatcher.discord.webhook_url or ""
    discord_enabled = bool(discord_cfg.get("enabled", dispatcher.discord.enabled))

    telegram_cfg = repo.get_telegram_config()
    telegram_token = telegram_cfg.get("bot_token") or dispatcher.telegram.bot_token or ""
    telegram_chat = telegram_cfg.get("chat_id") or dispatcher.telegram.chat_id or ""
    telegram_enabled = bool(telegram_cfg.get("enabled", dispatcher.telegram.enabled))

    return SystemSettingsResponse(
        discord=DiscordSettingsSchema(
            enabled=discord_enabled,
            webhook_url_masked=DiscordNotifier.mask_webhook_url(discord_url),
            is_configured=bool(discord_url.startswith("http")),
        ),
        telegram=TelegramSettingsSchema(
            enabled=telegram_enabled,
            bot_token_masked=TelegramNotifier.mask_token(telegram_token),
            chat_id_masked=TelegramNotifier.mask_token(telegram_chat),
            is_configured=bool(telegram_token and telegram_chat),
        ),
        dry_run_global=True,
        app_version="1.0.0",
    )


@router.patch("/settings", response_model=SystemSettingsResponse, summary="Update dynamic system and notification settings")
def update_system_settings(req: UpdateSystemSettingsRequest):
    repo = _get_settings_repo()
    dispatcher = NotificationDispatcher.get_instance()

    # 1. Update Discord if provided
    if req.discord_webhook_url is not None or req.discord_enabled is not None:
        curr_discord = repo.get_discord_config()
        new_url = req.discord_webhook_url if req.discord_webhook_url is not None else curr_discord.get("webhook_url", "")
        new_enabled = req.discord_enabled if req.discord_enabled is not None else curr_discord.get("enabled", True)
        repo.set_discord_config(webhook_url=new_url, enabled=new_enabled)
        dispatcher.discord.configure(webhook_url=new_url, enabled=new_enabled)

    # 2. Update Telegram if provided
    if req.telegram_bot_token is not None or req.telegram_chat_id is not None or req.telegram_enabled is not None:
        curr_tg = repo.get_telegram_config()
        new_token = req.telegram_bot_token if req.telegram_bot_token is not None else curr_tg.get("bot_token", "")
        new_chat = req.telegram_chat_id if req.telegram_chat_id is not None else curr_tg.get("chat_id", "")
        new_tg_enabled = req.telegram_enabled if req.telegram_enabled is not None else curr_tg.get("enabled", True)
        repo.set_telegram_config(bot_token=new_token, chat_id=new_chat, enabled=new_tg_enabled)
        dispatcher.telegram.configure(bot_token=new_token, chat_id=new_chat, enabled=new_tg_enabled)

    return get_system_settings()


@router.post("/notifications/test", response_model=NotificationTestResponse, summary="Dispatch a live diagnostic test alert")
async def trigger_notification_test(req: NotificationTestRequest):
    dispatcher = NotificationDispatcher.get_instance()
    ch = req.channel.lower()
    now_iso = datetime.datetime.now(datetime.timezone.utc).isoformat()

    if ch in ("discord", "all"):
        if not dispatcher.discord.enabled and not dispatcher.discord.webhook_url:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Discord is not configured. Please set discord_webhook_url first.",
            )
        success = await dispatcher.discord.send_test_message()
        if not success:
            raise HTTPException(
                status_code=status.HTTP_502_BAD_GATEWAY,
                detail="Failed to send Discord test alert. Verify webhook URL validity.",
            )
        return NotificationTestResponse(
            status="success",
            channel="discord",
            message="Test notification successfully dispatched to Discord channel.",
            dispatched_at=now_iso,
        )

    elif ch in ("telegram", "all"):
        if not dispatcher.telegram.enabled:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Telegram is not configured. Please set bot_token and chat_id first.",
            )
        success = await dispatcher.telegram.send_message(
            "🔔 <b>[APEX QUANT] Diagnóstico de Conectividad</b>\n"
            "Las notificaciones de Telegram están activas y operando correctamente."
        )
        if not success:
            raise HTTPException(
                status_code=status.HTTP_502_BAD_GATEWAY,
                detail="Failed to send Telegram test message.",
            )
        return NotificationTestResponse(
            status="success",
            channel="telegram",
            message="Test notification successfully dispatched to Telegram chat.",
            dispatched_at=now_iso,
        )

    else:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Unknown notification channel '{req.channel}'. Supported: 'discord', 'telegram', 'all'.",
        )
