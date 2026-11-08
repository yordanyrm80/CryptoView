import sys
from pathlib import Path

# Añadir raíz de bot al path
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

def load_data():
    conn = psycopg2.connect(**DB_CONFIG)
    query_btc = """
    SELECT "time", open, high, low, close, volume 
    FROM public.candles_1h 
    WHERE symbol = 'BTC/USDT' 
    ORDER BY "time" ASC;
    """
    df = pd.read_sql_query(query_btc, conn)
    conn.close()

    df["time"] = pd.to_datetime(df["time"])
    df.set_index("time", inplace=True)

    # Indicadores
    close = df["close"]
    high = df["high"]
    low = df["low"]

    # ATR 14
    tr1 = high - low
    tr2 = (high - close.shift(1)).abs()
    tr3 = (low - close.shift(1)).abs()
    tr = pd.concat([tr1, tr2, tr3], axis=1).max(axis=1)
    df["atr_14"] = tr.rolling(window=14).mean().fillna(close * 0.02)

    # RSI 14
    delta = close.diff()
    gain = (delta.where(delta > 0, 0)).rolling(window=14).mean()
    loss = (-delta.where(delta < 0, 0)).rolling(window=14).mean()
    rs = gain / loss.replace(0, np.nan)
    df["rsi_14"] = (100 - (100 / (1 + rs))).fillna(50.0)

    # Daily EMA 200 y RSI diario
    df["ema_200_daily"] = close.ewm(span=4800, adjust=False).mean()
    df["dist_ema_200"] = close / df["ema_200_daily"]

    daily_df = df.resample("1D").agg({"close": "last"})
    d_delta = daily_df["close"].diff()
    d_gain = (d_delta.where(d_delta > 0, 0)).rolling(window=14).mean()
    d_loss = (-d_delta.where(d_delta < 0, 0)).rolling(window=14).mean()
    d_rs = d_gain / d_loss.replace(0, np.nan)
    daily_df["rsi_daily"] = (100 - (100 / (1 + d_rs))).fillna(50.0)
    df["rsi_daily"] = daily_df["rsi_daily"].reindex(df.index, method="ffill").fillna(50.0)

    return df

def run_simulation_engine(
    df: pd.DataFrame,
    initial_btc: float = 1.0,
    initial_powder: float = 2000.0,
    reinvest_rate: float = 0.0,  # Fracción de ganancia reinvertida a la pólvora (0.0 a 1.0)
    powder_cap: float = None,     # Tope máximo de pólvora (opcional)
    convert_at_bottom: bool = False, # Inyección masiva de pólvora a BTC en capitulación
    fee: float = 0.001
):
    vault_btc = initial_btc
    current_powder_budget = initial_powder
    avail_usdt = initial_powder
    tranches = []
    trades = 0
    max_powder_reached = initial_powder

    take_profit_pct = 0.045  # 4.5% TP

    for i in range(len(df)):
        price = df["close"].iloc[i]
        high = df["high"].iloc[i]
        atr = df["atr_14"].iloc[i]
        rsi = df["rsi_14"].iloc[i]
        dist = df["dist_ema_200"].iloc[i]
        rsi_d = df["rsi_daily"].iloc[i]

        # 1. Comprobar ventas / Take Profit
        active_tranches = [t for t in tranches if t["active"]]
        for t in active_tranches:
            if high >= t["tp_price"]:
                t["active"] = False
                sell_price = t["tp_price"]
                gross_usdt = t["amount"] * sell_price * (1.0 - fee)
                profit_usdt = gross_usdt - t["cost_usdt"]

                # Recuperar principal invertido a la pólvora disponible
                avail_usdt += t["cost_usdt"]

                if profit_usdt > 0:
                    # Determinar qué parte se reinvierte a pólvora y qué parte va a la bóveda BTC
                    if powder_cap is not None and current_powder_budget >= powder_cap:
                        # Si ya alcanzó el tope, el 100% va a la bóveda
                        rate = 0.0
                    else:
                        rate = reinvest_rate

                    reinvest_amt = profit_usdt * rate
                    harvest_amt = profit_usdt * (1.0 - rate)

                    # Crecer pólvora
                    current_powder_budget += reinvest_amt
                    avail_usdt += reinvest_amt
                    if current_powder_budget > max_powder_reached:
                        max_powder_reached = current_powder_budget

                    # Cosechar a Satoshis en Bóveda
                    if harvest_amt > 0:
                        bought_btc = (harvest_amt * (1.0 - fee)) / sell_price
                        vault_btc += bought_btc

                trades += 1

        # 2. Mecanismo opcional: Conversión en Capitulación (Comprar suelo con pólvora crecida)
        if convert_at_bottom and dist < 0.72 and rsi_d < 30.0 and avail_usdt > 1000.0:
            convert_amount = avail_usdt * 0.50  # Convierte el 50% de la pólvora disponible
            avail_usdt -= convert_amount
            current_powder_budget -= convert_amount
            bought_sats = (convert_amount * (1.0 - fee)) / price
            vault_btc += bought_sats
            trades += 1

        # 3. Comprobar entradas (Tramos dinámicos proporcionales a la pólvora actual)
        active_count = len([t for t in tranches if t["active"]])
        tranche_budget = current_powder_budget / 3.0

        if active_count < 3 and avail_usdt >= tranche_budget:
            should_buy = False
            if active_count == 0 and rsi < 45.0:
                should_buy = True
            elif active_count > 0:
                last_buy_price = [t["buy_price"] for t in tranches if t["active"]][-1]
                if price <= (last_buy_price - 1.5 * atr):
                    should_buy = True

            if should_buy:
                cost = tranche_budget
                avail_usdt -= cost
                btc_bought = (cost * (1.0 - fee)) / price
                tp = price * (1.0 + take_profit_pct)
                tranches.append({
                    "active": True,
                    "buy_price": price,
                    "tp_price": tp,
                    "amount": btc_bought,
                    "cost_usdt": cost
                })

    # Liquidación final
    final_price = df["close"].iloc[-1]
    active_btc_in_tranches = sum(t["amount"] for t in tranches if t["active"])
    unrealized_btc = (avail_usdt / final_price) + active_btc_in_tranches
    total_btc = vault_btc + unrealized_btc

    return {
        "vault_btc": vault_btc,
        "total_btc": total_btc,
        "final_usd": total_btc * final_price,
        "trades": trades,
        "max_powder": max_powder_reached,
    }

def main():
    print("==============================================================================")
    print("SIMULACIÓN: INTERÉS COMPUESTO PARA ACUMULAR EL MÁXIMO DE BITCOIN (2017-2026)")
    print("==============================================================================\n")

    print("Cargando 79,000+ velas de CryptoViewPruebas...", flush=True)
    df = load_data()
    final_price = df["close"].iloc[-1]

    bh_btc = 1.0
    bh_usd = bh_btc * final_price

    # 1. Pólvora Fija (Sin Compounding): 100% ganancia va a BTC
    r_fija = run_simulation_engine(df, initial_powder=2000.0, reinvest_rate=0.0)

    # 2. Compounding Moderado 30/70 (30% reinvertido en pólvora, 70% a BTC)
    r_c30 = run_simulation_engine(df, initial_powder=2000.0, reinvest_rate=0.30)

    # 3. Compounding Híbrido 50/50 (50% reinvertido en pólvora, 50% a BTC)
    r_c50 = run_simulation_engine(df, initial_powder=2000.0, reinvest_rate=0.50)

    # 4. Compounding Agresivo 70/30 (70% reinvertido en pólvora, 30% a BTC)
    r_c70 = run_simulation_engine(df, initial_powder=2000.0, reinvest_rate=0.70)

    # 5. Compounding por Fases: Crecer pólvora hasta $10k, luego 100% a BTC
    r_cap10k = run_simulation_engine(df, initial_powder=2000.0, reinvest_rate=1.0, powder_cap=10000.0)

    # 6. Compounding con Cosecha Masiva en Suelos de Ciclo (Capitulation Injection)
    r_bottom = run_simulation_engine(df, initial_powder=2000.0, reinvest_rate=0.50, convert_at_bottom=True)

    table_data = [
        [
            "BENCHMARK: Buy & Hold",
            f"{bh_btc:.4f} BTC",
            "0.00%",
            f"${bh_usd:,.2f}",
            "$0",
            0,
            "100% pasivo"
        ],
        [
            "A. Pólvora Fija (Sin Compounding)",
            f"{r_fija['total_btc']:.4f} BTC",
            f"{((r_fija['total_btc'] / bh_btc) - 1.0) * 100:+.2f}%",
            f"${r_fija['final_usd']:,.2f}",
            f"${r_fija['max_powder']:,.0f}",
            r_fija['trades'],
            "100% profit a Satoshis ($2k fijo)"
        ],
        [
            "B. Compounding 30% Pólvora / 70% BTC",
            f"{r_c30['total_btc']:.4f} BTC",
            f"{((r_c30['total_btc'] / bh_btc) - 1.0) * 100:+.2f}%",
            f"${r_c30['final_usd']:,.2f}",
            f"${r_c30['max_powder']:,.0f}",
            r_c30['trades'],
            "La pólvora crece suavemente"
        ],
        [
            "C. Compounding Híbrido 50/50",
            f"{r_c50['total_btc']:.4f} BTC",
            f"{((r_c50['total_btc'] / bh_btc) - 1.0) * 100:+.2f}%",
            f"${r_c50['final_usd']:,.2f}",
            f"${r_c50['max_powder']:,.0f}",
            r_c50['trades'],
            "Equilibrio: pólvora crece 50%, cosecha 50%"
        ],
        [
            "D. Compounding Agresivo 70/30",
            f"{r_c70['total_btc']:.4f} BTC",
            f"{((r_c70['total_btc'] / bh_btc) - 1.0) * 100:+.2f}%",
            f"${r_c70['final_usd']:,.2f}",
            f"${r_c70['max_powder']:,.0f}",
            r_c70['trades'],
            "70% hace bola de nieve a pólvora"
        ],
        [
            "E. Por Fases: Crecer a $10k -> 100% BTC",
            f"{r_cap10k['total_btc']:.4f} BTC",
            f"{((r_cap10k['total_btc'] / bh_btc) - 1.0) * 100:+.2f}%",
            f"${r_cap10k['final_usd']:,.2f}",
            f"${r_cap10k['max_powder']:,.0f}",
            r_cap10k['trades'],
            "Primero escala el motor a $10k"
        ],
        [
            "F. 50/50 + Inyección en Suelos Macro",
            f"{r_bottom['total_btc']:.4f} BTC",
            f"{((r_bottom['total_btc'] / bh_btc) - 1.0) * 100:+.2f}%",
            f"${r_bottom['final_usd']:,.2f}",
            f"${r_bottom['max_powder']:,.0f}",
            r_bottom['trades'],
            "Convierte pólvora en valles de pánico"
        ],
    ]

    headers = [
        "Variante de Interés Compuesto",
        "BTC Final",
        "Alfa Sats vs B&H",
        "Valor USD Final",
        "Pólvora Máx",
        "Trades",
        "Mecánica de Reinversión"
    ]

    print("\n" + tabulate(table_data, headers=headers, tablefmt="fancy_grid"))
    print(f"\n* Precio final BTC al corte: ${final_price:,.2f}")
    print(f"* Periodo analizado: {df.index[0].strftime('%d-%b-%Y')} al {df.index[-1].strftime('%d-%b-%Y')} ({len(df):,} horas)")

if __name__ == "__main__":
    main()
