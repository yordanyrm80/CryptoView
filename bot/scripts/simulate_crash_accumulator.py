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

    # RSI 14 horario
    delta = close.diff()
    gain = (delta.where(delta > 0, 0)).rolling(14).mean()
    loss = (-delta.where(delta < 0, 0)).rolling(14).mean()
    df["rsi_14"] = (100 - (100 / (1 + gain / loss.replace(0, np.nan)))).fillna(50.0)

    # Daily EMA 200 y RSI diario
    df["ema_200_daily"] = close.ewm(span=4800, adjust=False).mean()
    df["dist_ema_200"] = close / df["ema_200_daily"]

    daily_df = df.resample("1D").agg({"close": "last"})
    d_delta = daily_df["close"].diff()
    d_gain = (d_delta.where(d_delta > 0, 0)).rolling(14).mean()
    d_loss = (-d_delta.where(d_delta < 0, 0)).rolling(14).mean()
    daily_df["rsi_daily"] = (100 - (100 / (1 + d_gain / d_loss.replace(0, np.nan)))).fillna(50.0)
    df["rsi_daily"] = daily_df["rsi_daily"].reindex(df.index, method="ffill").fillna(50.0)

    final_price = close.iloc[-1]
    start_price = close.iloc[0]
    fee = 0.001

    def run_strategy(crash_alloc_pct: float):
        """
        - crash_alloc_pct: qué % de la caja de USDT disponible se gasta en comprar BTC
          cuando hay una capitulación macro (dist_ema_200 < 0.70 y rsi_daily < 32).
        """
        budget_usdt = 2000.0
        avail_usdt = 2000.0
        vault_btc = 0.0
        tranches = []
        trades = 0
        crash_buys = []
        last_crash_bar = -9999

        for i in range(len(df)):
            p = close.iloc[i]
            h = high.iloc[i]
            atr = df["atr_14"].iloc[i]
            rsi = df["rsi_14"].iloc[i]
            dist = df["dist_ema_200"].iloc[i]
            rsi_d = df["rsi_daily"].iloc[i]

            # 1. Comprobar Take Profit de tramos de trading
            for t in [t for t in tranches if t["active"]]:
                if h >= t["tp"]:
                    t["active"] = False
                    gross = t["amount"] * t["tp"] * (1.0 - fee)
                    profit = gross - t["cost"]
                    budget_usdt += profit
                    avail_usdt += gross
                    trades += 1

            # 2. DISPARADOR MACRO: ¿Gran Caída / Capitulación de Ciclo?
            # Filtro: Precio más de 32% bajo la EMA 200 y RSI diario en pánico (<32)
            # Solo dispara una vez cada 60 días (1,440 horas) para no gastar todo en un solo día
            is_macro_crash = (dist < 0.68 and rsi_d < 32.0)
            if crash_alloc_pct > 0 and is_macro_crash and (i - last_crash_bar > 1440) and avail_usdt > 1000.0:
                spend = avail_usdt * crash_alloc_pct
                avail_usdt -= spend
                budget_usdt -= spend  # Se retira de la pólvora para transferirlo a la bóveda fría
                bought_btc = (spend * (1.0 - fee)) / p
                vault_btc += bought_btc
                last_crash_bar = i
                crash_buys.append({
                    "date": df.index[i].strftime("%Y-%m-%d"),
                    "price": p,
                    "spent_usdt": spend,
                    "btc": bought_btc
                })

            # 3. Entradas estándar de trading en USDT (3 tramos proporcionales al budget)
            active = [t for t in tranches if t["active"]]
            tb = budget_usdt / 3.0
            if len(active) < 3 and avail_usdt >= tb:
                buy = False
                if len(active) == 0 and rsi < 45.0:
                    buy = True
                elif len(active) > 0 and p <= (active[-1]["p"] - 1.5 * atr):
                    buy = True

                if buy:
                    avail_usdt -= tb
                    tranches.append({
                        "active": True,
                        "p": p,
                        "tp": p * 1.045,
                        "amount": (tb * (1.0 - fee)) / p,
                        "cost": tb
                    })

        # Liquidación final
        active_btc = sum(t["amount"] for t in tranches if t["active"])
        unrealized_btc = active_btc + (avail_usdt / final_price)
        total_btc = vault_btc + unrealized_btc
        total_usd = total_btc * final_price

        return {
            "vault_btc": vault_btc,
            "total_btc": total_btc,
            "total_usd": total_usd,
            "trades": trades,
            "crash_buys": crash_buys
        }

    # Simulamos diferentes niveles de agresión en las grandes caídas:
    # 0%: No compra en caídas (100% USDT compounding puro)
    # 25%: Desvía el 25% del cash en caídas
    # 50%: Desvía el 50% del cash en caídas
    # 75%: Desvía el 75% del cash en caídas
    r_0 = run_strategy(crash_alloc_pct=0.0)
    r_25 = run_strategy(crash_alloc_pct=0.25)
    r_50 = run_strategy(crash_alloc_pct=0.50)
    r_75 = run_strategy(crash_alloc_pct=0.75)

    bh_btc = (2000.0 * (1.0 - fee)) / start_price
    bh_usd = bh_btc * final_price

    table_data = [
        [
            "BENCHMARK: Buy & Hold en 2017",
            f"${bh_usd:,.2f}",
            f"{bh_btc:.4f} BTC",
            "0.00%",
            0,
            "Compró a $4,950 en 2017"
        ],
        [
            "1. Bot USDT Puro (0% compra en caídas)",
            f"${r_0['total_usd']:,.2f}",
            f"{r_0['total_btc']:.4f} BTC",
            f"{((r_0['total_btc'] / bh_btc) - 1.0) * 100:+.2f}%",
            len(r_0['crash_buys']),
            "Todo en USDT, compra al final"
        ],
        [
            "2. Bot USDT + Compra 25% en Grandes Caídas",
            f"${r_25['total_usd']:,.2f}",
            f"{r_25['total_btc']:.4f} BTC",
            f"{((r_25['total_btc'] / bh_btc) - 1.0) * 100:+.2f}%",
            len(r_25['crash_buys']),
            "Desvía 25% cash en pánicos"
        ],
        [
            "3. Bot USDT + Compra 50% en Grandes Caídas",
            f"${r_50['total_usd']:,.2f}",
            f"{r_50['total_btc']:.4f} BTC",
            f"{((r_50['total_btc'] / bh_btc) - 1.0) * 100:+.2f}%",
            len(r_50['crash_buys']),
            "Desvía 50% cash en pánicos"
        ],
        [
            "4. Bot USDT + Compra 75% en Grandes Caídas",
            f"${r_75['total_usd']:,.2f}",
            f"{r_75['total_btc']:.4f} BTC",
            f"{((r_75['total_btc'] / bh_btc) - 1.0) * 100:+.2f}%",
            len(r_75['crash_buys']),
            "Desvía 75% cash en pánicos"
        ],
    ]

    headers = [
        "Estrategia (Todas con $2,000 USDT de inicio)",
        "Valor USD Final",
        "BTC Final",
        "Alfa vs B&H",
        "Compras Macro",
        "Mecánica"
    ]

    print("==============================================================================")
    print("SIMULACIÓN: BOT DE USDT QUE ACUMULA BITCOIN SOLO EN LAS GRANDES CAÍDAS")
    print("==============================================================================\n")
    print(tabulate(table_data, headers=headers, tablefmt="fancy_grid"))

    if r_50['crash_buys']:
        print("\n📍 Detalle de compras macro en el Modelo 50% (¿Cuándo y a qué precio compró?):")
        for b in r_50['crash_buys']:
            print(f"   * Fecha: {b['date']} | Precio BTC: ${b['price']:,.2f} | Inversión: ${b['spent_usdt']:,.2f} USDT | BTC Adquirido: {b['btc']:.4f} BTC")

if __name__ == "__main__":
    main()
