import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

import psycopg2
import pandas as pd
import numpy as np
from tabulate import tabulate

DB_CONFIG = {
    "host": "127.0.0.1",
    "port": 5432,
    "user": "postgres",
    "password": "postgres",
    "dbname": "CryptoViewPruebas",
}

def main():
    conn = psycopg2.connect(**DB_CONFIG)
    query = """
    SELECT "time", open, high, low, close, volume 
    FROM public.candles_1h 
    WHERE symbol = 'BTC/USDT' 
    ORDER BY "time" ASC;
    """
    df = pd.read_sql_query(query, conn)
    conn.close()

    df["time"] = pd.to_datetime(df["time"])
    df.set_index("time", inplace=True)

    close = df["close"]
    high = df["high"]
    low = df["low"]

    # ATR 14
    tr1 = high - low
    tr2 = (high - close.shift(1)).abs()
    tr3 = (low - close.shift(1)).abs()
    df["atr_14"] = pd.concat([tr1, tr2, tr3], axis=1).max(axis=1).rolling(14).mean().fillna(close * 0.02)

    # RSI 14
    delta = close.diff()
    gain = (delta.where(delta > 0, 0)).rolling(14).mean()
    loss = (-delta.where(delta < 0, 0)).rolling(14).mean()
    df["rsi_14"] = (100 - (100 / (1 + gain / loss.replace(0, np.nan)))).fillna(50.0)

    final_price = close.iloc[-1]
    start_price = close.iloc[0]
    fee = 0.001

    # ==========================================================================
    # 1. BOT GANAR USDT (Compounding Exponencial en Dólares, $2,000 iniciales)
    # ==========================================================================
    budget_usdt = 2000.0
    avail_usdt = 2000.0
    tranches_usdt = []
    trades_usdt = 0

    for i in range(len(df)):
        p = close.iloc[i]
        h = high.iloc[i]
        atr = df["atr_14"].iloc[i]
        rsi = df["rsi_14"].iloc[i]

        # Take Profit
        for t in [t for t in tranches_usdt if t["active"]]:
            if h >= t["tp"]:
                t["active"] = False
                gross = t["amount"] * t["tp"] * (1.0 - fee)
                profit = gross - t["cost"]
                budget_usdt += profit
                avail_usdt += gross
                trades_usdt += 1

        # Entradas (3 tramos proporcionales al presupuesto compuesto)
        active = [t for t in tranches_usdt if t["active"]]
        tb = budget_usdt / 3.0
        if len(active) < 3 and avail_usdt >= tb:
            buy = False
            if len(active) == 0 and rsi < 45.0:
                buy = True
            elif len(active) > 0 and p <= (active[-1]["p"] - 1.5 * atr):
                buy = True

            if buy:
                avail_usdt -= tb
                tranches_usdt.append({
                    "active": True,
                    "p": p,
                    "tp": p * 1.045,
                    "amount": (tb * (1.0 - fee)) / p,
                    "cost": tb
                })

    active_btc_usdt = sum(t["amount"] for t in tranches_usdt if t["active"])
    total_usdt_final = avail_usdt + (active_btc_usdt * final_price)
    btc_comprable_usdt_bot = total_usdt_final / final_price

    # ==========================================================================
    # 2. BOT SATOSHI LEECH (Pólvora Fija $2,000, 100% Ganancias a BTC)
    # ==========================================================================
    budget_leech = 2000.0
    avail_leech = 2000.0
    vault_btc = 0.0
    tranches_leech = []
    trades_leech = 0

    for i in range(len(df)):
        p = close.iloc[i]
        h = high.iloc[i]
        atr = df["atr_14"].iloc[i]
        rsi = df["rsi_14"].iloc[i]

        for t in [t for t in tranches_leech if t["active"]]:
            if h >= t["tp"]:
                t["active"] = False
                gross = t["amount"] * t["tp"] * (1.0 - fee)
                profit = gross - t["cost"]
                avail_leech += t["cost"]
                if profit > 0:
                    vault_btc += (profit * (1.0 - fee)) / t["tp"]
                trades_leech += 1

        active = [t for t in tranches_leech if t["active"]]
        tb = budget_leech / 3.0
        if len(active) < 3 and avail_leech >= tb:
            buy = False
            if len(active) == 0 and rsi < 45.0:
                buy = True
            elif len(active) > 0 and p <= (active[-1]["p"] - 1.5 * atr):
                buy = True

            if buy:
                avail_leech -= tb
                tranches_leech.append({
                    "active": True,
                    "p": p,
                    "tp": p * 1.045,
                    "amount": (tb * (1.0 - fee)) / p,
                    "cost": tb
                })

    active_btc_leech = sum(t["amount"] for t in tranches_leech if t["active"])
    unrealized_leech_btc = active_btc_leech + (avail_leech / final_price)
    total_btc_leech = vault_btc + unrealized_leech_btc

    # ==========================================================================
    # 3. BENCHMARK: ¿Y si compraras $2,000 de BTC al inicio (Buy & Hold puro)?
    # ==========================================================================
    bh_btc = (2000.0 * (1.0 - fee)) / start_price
    bh_usd = bh_btc * final_price

    # Imprimir Comparativa
    table_data = [
        [
            "1. BUY & HOLD ($2,000 en BTC en 2017)",
            f"${bh_usd:,.2f}",
            f"{bh_btc:.4f} BTC",
            "Base (100% pasivo)",
            0
        ],
        [
            "2. BOT GANAR USDT (Compounding Puro)",
            f"${total_usdt_final:,.2f}",
            f"{btc_comprable_usdt_bot:.4f} BTC",
            f"{((total_usdt_final / bh_usd) - 1.0) * 100:+.2f}%",
            trades_usdt
        ],
        [
            "3. BOT SATOSHI LEECH (Pólvora Fija a BTC)",
            f"${total_btc_leech * final_price:,.2f}",
            f"{total_btc_leech:.4f} BTC",
            f"{((total_btc_leech / bh_btc) - 1.0) * 100:+.2f}%",
            trades_leech
        ],
    ]

    headers = [
        "Estrategia (Todas con $2,000 USDT de inicio)",
        "Valor Final en USD",
        "Bitcoins Finales",
        "Rendimiento vs B&H",
        "Trades"
    ]

    print("==============================================================================")
    print("COMPARATIVA RIGUROSA: AMBOS BOTS INICIANDO CON EXACTAMENTE $2,000 USDT")
    print(f"Periodo: {df.index[0].strftime('%Y-%m-%d')} a {df.index[-1].strftime('%Y-%m-%d')} (Precio inicial: ${start_price:,.2f} | Final: ${final_price:,.2f})")
    print("==============================================================================\n")
    print(tabulate(table_data, headers=headers, tablefmt="fancy_grid"))

if __name__ == "__main__":
    main()
