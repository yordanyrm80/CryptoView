import asyncio
import os
import sys
from dotenv import load_dotenv

# Ensure UTF-8 output on Windows console
if sys.platform == "win32":
    try:
        sys.stdout.reconfigure(encoding="utf-8")
        sys.stderr.reconfigure(encoding="utf-8")
    except Exception:
        pass

# Ensure root directory is on PYTHONPATH
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from src.core.discord_notifier import DiscordNotifier
from src.storage.database import DatabaseManager
from src.storage.settings_repository import SettingsRepository


async def main():
    load_dotenv()
    print("=" * 60)
    print("🤖 APEX QUANT - DIAGNÓSTICO DE NOTIFICACIONES DISCORD")
    print("=" * 60)

    db = DatabaseManager()
    repo = SettingsRepository(db)
    notifier = DiscordNotifier(settings_repo=repo)

    if not notifier.enabled and not notifier.webhook_url:
        print("❌ ERROR: Discord Webhook no está configurado ni en PostgreSQL ni en .env")
        print("👉 Puedes configurarlo mediante la API (PATCH /api/v1/system/settings) o en el archivo .env:")
        print("   DISCORD_WEBHOOK_URL=https://discord.com/api/webhooks/...")
        print("=" * 60)
        sys.exit(1)

    print(f"📡 Conectando con Discord Webhook ({notifier.mask_webhook_url(notifier.webhook_url)})...")

    # 1. Connectivity Test
    print("1/3 Enviando alerta de conectividad y sonido...")
    ok = await notifier.send_test_message()
    if ok:
        print("   ✅ Alerta de conectividad enviada con éxito.")
    else:
        print("   ❌ Falló el envío. Verifica que la URL del webhook sea válida.")
        sys.exit(1)

    await asyncio.sleep(1)

    # 2. Simulated Limit Buy Execution
    print("2/3 Enviando simulación de orden LIMIT BUY ejecutada...")
    await notifier.notify_buy(
        bot_id="kucoin_btc_runner",
        tranche_index=1,
        symbol="BTC/USDT",
        price=63450.00,
        amount=0.003152,
        allocated_usdt=200.00,
        target_tp=65353.50,
        is_dry_run=False,
    )
    print("   ✅ Tarjeta verde de compra enviada.")

    await asyncio.sleep(1)

    # 3. Simulated Take Profit Execution
    print("3/3 Enviando simulación de TAKE PROFIT realizado...")
    await notifier.notify_sell(
        bot_id="kucoin_btc_runner",
        tranche_index=1,
        symbol="BTC/USDT",
        sell_price=65353.50,
        profit_usdt=6.00,
        is_dry_run=False,
    )
    print("   ✅ Tarjeta dorada de take profit enviada.")

    print("=" * 60)
    print("🎉 ¡TODO LISTO! Revisa la app de Discord en tu teléfono o PC.")
    print("=" * 60)


if __name__ == "__main__":
    asyncio.run(main())
