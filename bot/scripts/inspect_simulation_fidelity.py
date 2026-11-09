import urllib.request
import json
import ssl

BASE_URL = "https://129-146-110-196.sslip.io"
API_KEY = "aa0d07ca7079caf19492d0fc4a762c593b3e02e205c669ae60de5cbbd66979c2"

ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE

def fetch(path):
    url = f"{BASE_URL}{path}"
    req = urllib.request.Request(url, headers={
        "Content-Type": "application/json",
        "X-API-Key": API_KEY
    })
    try:
        with urllib.request.urlopen(req, context=ctx, timeout=15) as resp:
            return json.loads(resp.read().decode('utf-8'))
    except Exception as e:
        print(f"Error consultando {path}: {e}")
        return None

def analyze():
    bot_id = "apex_titan_btc"
    print(f"============================================================")
    print(f"AUDITORÍA DE FIDELIDAD ALGORÍTMICA: {bot_id}")
    print(f"============================================================")

    # 1. Bot details
    bot = fetch(f"/api/v1/bots/{bot_id}")
    if not bot:
        print("No se pudo obtener el bot.")
        return

    print("\n--- 1. CONFIGURACIÓN Y ESTADO GENERAL ---")
    print(f"Estrategia:            {bot.get('strategy_name')}")
    print(f"Estado / Modo:         {bot.get('status')} | Dry Run: {bot.get('dry_run')}")
    print(f"Capital Inicial:       ${bot.get('budget')} USDT")
    print(f"Capital Asignado:      ${bot.get('allocated_budget')} USDT")
    print(f"Capital Invertido:     ${bot.get('invested_usdt')} USDT")
    print(f"Capital Disponible:    ${bot.get('available_usdt')} USDT")
    print(f"Equity Actual:         ${bot.get('current_equity_usdt')} USDT")
    print(f"PnL Realizado:         ${bot.get('realized_pnl_usdt')} USDT ({bot.get('total_trades')} trades, {bot.get('win_rate_pct')}% win rate)")
    print(f"PnL No Realizado:      ${bot.get('unrealized_pnl_usdt')} USDT")
    print(f"Régimen de Mercado:    {bot.get('current_market_regime')} (RSI 14: {bot.get('current_rsi')})")

    # 2. Tranches
    tranches = fetch(f"/api/v1/bots/{bot_id}/tranches") or []
    print(f"\n--- 2. TRAMOS ACTIVOS / REGISTRADOS ({len(tranches)}) ---")
    for t in tranches:
        lvl = t.get('level', t.get('tranche_index'))
        status = t.get('status')
        bp = t.get('buy_price')
        tp = t.get('take_profit_price')
        ts = t.get('trailing_stop_price')
        amount = t.get('amount', t.get('crypto_amount'))
        cost = t.get('cost_usdt', t.get('invested_amount'))
        print(f"  * Tramo #{lvl:<2} | Estado: {status:<8} | Buy: ${bp} | TP: ${tp} | Trailing: ${ts} | Cantidad: {amount} BTC (~${cost} USDT)")

    # 3. Orders
    orders = fetch(f"/api/v1/bots/{bot_id}/orders") or []
    print(f"\n--- 3. HISTORIAL DE ÓRDENES ({len(orders)}) ---")
    for o in orders:
        side = o.get('side', '').upper()
        price = o.get('price')
        qty = o.get('amount')
        status = o.get('status')
        filled_at = o.get('filled_at') or o.get('updated_at') or o.get('created_at')
        role = o.get('type', '')
        print(f"  * {filled_at} | {side:<4} {qty} BTC @ ${price:<9} | Status: {status:<8} | ID: {o.get('order_id')}")

    # 4. Plateau status & Transactions
    plateau = fetch(f"/api/v1/bots/{bot_id}/plateau-status")
    print(f"\n--- 4. ESTADO DE MESETA (PLATEAU RECOVERY) ---")
    if plateau:
        print(f"  En meseta:             {plateau.get('is_plateau')}")
        print(f"  Días estancado:        {plateau.get('days_inactive')}")
        print(f"  Inyección sugerida:    {plateau.get('injection_recommended')}")
        print(f"  Diagnóstico:           {plateau.get('advice')}")
    else:
        print("  Sin información de meseta.")

    # 5. Audit Events
    events = fetch(f"/api/v1/bots/{bot_id}/events") or []
    print(f"\n--- 5. BITÁCORA DE EVENTOS Y AUDITORÍA (Últimos 15) ---")
    for ev in events[:15]:
        ts = ev.get('created_at')
        lvl = ev.get('level', 'INFO')
        etype = ev.get('event_type')
        msg = ev.get('message')
        print(f"  [{ts}] [{lvl:<5}] {etype}: {msg}")

if __name__ == "__main__":
    analyze()
