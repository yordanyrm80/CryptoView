import sys
import os
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

def load_data_from_db():
    print("1. Conectando a PostgreSQL local (CryptoViewPruebas)...", flush=True)
    conn = psycopg2.connect(**DB_CONFIG)
    
    query_btc = """
    SELECT "time", open, high, low, close, volume 
    FROM public.candles_1h 
    WHERE symbol = 'BTC/USDT' 
    ORDER BY "time" ASC;
    """
    df_btc = pd.read_sql_query(query_btc, conn)
    df_btc["time"] = pd.to_datetime(df_btc["time"])
    df_btc.set_index("time", inplace=True)

    query_kcs = """
    SELECT "time", close as kcs_close 
    FROM public.candles_1h 
    WHERE symbol = 'KCS/USDT' 
    ORDER BY "time" ASC;
    """
    df_kcs = pd.read_sql_query(query_kcs, conn)
    df_kcs["time"] = pd.to_datetime(df_kcs["time"])
    df_kcs.set_index("time", inplace=True)
    conn.close()

    df = df_btc.join(df_kcs, how="inner")
    df["kcs_btc_ratio"] = df["kcs_close"] / df["close"]
    print(f"   -> Total de velas alineadas: {len(df):,} ({df.index[0].strftime('%Y-%m-%d')} a {df.index[-1].strftime('%Y-%m-%d')})", flush=True)
    return df

def compute_indicators(df: pd.DataFrame) -> pd.DataFrame:
    print("2. Calculando indicadores técnicos cuantitativos...", flush=True)
    df = df.copy()
    close = df["close"]
    high = df["high"]
    low = df["low"]

    # 1. Daily EMA 200 (4,800 periodos horarios)
    df["ema_200_daily"] = close.ewm(span=4800, adjust=False).mean()
    df["dist_ema_200"] = close / df["ema_200_daily"]

    # 2. ATR 14 horario
    tr1 = high - low
    tr2 = (high - close.shift(1)).abs()
    tr3 = (low - close.shift(1)).abs()
    tr = pd.concat([tr1, tr2, tr3], axis=1).max(axis=1)
    df["atr_14"] = tr.rolling(window=14).mean().fillna(close * 0.02)

    # 3. RSI 14 horario
    delta = close.diff()
    gain = (delta.where(delta > 0, 0)).rolling(window=14).mean()
    loss = (-delta.where(delta < 0, 0)).rolling(window=14).mean()
    rs = gain / loss.replace(0, np.nan)
    df["rsi_14"] = (100 - (100 / (1 + rs))).fillna(50.0)

    # 4. Indicadores diarios reales resampleados
    daily_df = df.resample("1D").agg({"close": "last", "kcs_btc_ratio": "last"})
    d_delta = daily_df["close"].diff()
    d_gain = (d_delta.where(d_delta > 0, 0)).rolling(window=14).mean()
    d_loss = (-d_delta.where(d_delta < 0, 0)).rolling(window=14).mean()
    d_rs = d_gain / d_loss.replace(0, np.nan)
    daily_df["rsi_daily"] = (100 - (100 / (1 + d_rs))).fillna(50.0)

    # RSI del ratio KCS/BTC diario
    r_delta = daily_df["kcs_btc_ratio"].diff()
    r_gain = (r_delta.where(r_delta > 0, 0)).rolling(window=14).mean()
    r_loss = (-r_delta.where(r_delta < 0, 0)).rolling(window=14).mean()
    r_rs = r_gain / r_loss.replace(0, np.nan)
    daily_df["ratio_rsi_daily"] = (100 - (100 / (1 + r_rs))).fillna(50.0)

    # Unir hacia atrás (reindex / forward fill)
    df["rsi_daily"] = daily_df["rsi_daily"].reindex(df.index, method="ffill").fillna(50.0)
    df["ratio_rsi_daily"] = daily_df["ratio_rsi_daily"].reindex(df.index, method="ffill").fillna(50.0)

    return df

# ==============================================================================
# MODELO 1: REBALANCEADOR ASIMÉTRICO DE CICLO (Macro Dynamic Rebalancer)
# ==============================================================================
def simulate_model_1_macro_rebalance(df: pd.DataFrame, initial_btc: float = 1.0, fee: float = 0.001):
    btc = initial_btc
    usdt = 0.0
    trades = 0
    in_cash = False

    for i in range(len(df)):
        price = df["close"].iloc[i]
        dist = df["dist_ema_200"].iloc[i]
        rsi_d = df["rsi_daily"].iloc[i]

        # Venta macro en sobreextensión extrema (percentil 95+ de ciclo)
        if not in_cash and dist > 1.50 and rsi_d > 68.0:
            sell_btc = btc * 0.35  # Vende 35% de BTC a USDT
            proceeds = sell_btc * price * (1.0 - fee)
            btc -= sell_btc
            usdt += proceeds
            in_cash = True
            trades += 1

        # Recompra macro en suelo / invierno (precio bajo EMA 200 o RSI en pánico)
        elif in_cash and (dist < 0.78 or rsi_d < 32.0):
            buy_btc = (usdt * (1.0 - fee)) / price
            btc += buy_btc
            usdt = 0.0
            in_cash = False
            trades += 1

    final_price = df["close"].iloc[-1]
    total_btc = btc + (usdt / final_price)
    return total_btc, trades

# ==============================================================================
# MODELO 2: THE SATOSHI LEECH (Free Satoshi Harvest con Obrero en USDT)
# ==============================================================================
def simulate_model_2_satoshi_leech(df: pd.DataFrame, initial_btc: float = 1.0, powder_usdt: float = 2000.0, fee: float = 0.001):
    vault_btc = initial_btc
    avail_usdt = powder_usdt
    tranches = []
    trades = 0

    take_profit_pct = 0.045
    tranche_budget = powder_usdt / 3.0

    for i in range(len(df)):
        price = df["close"].iloc[i]
        high = df["high"].iloc[i]
        atr = df["atr_14"].iloc[i]
        rsi = df["rsi_14"].iloc[i]

        active_tranches = [t for t in tranches if t["active"]]
        for t in active_tranches:
            if high >= t["tp_price"]:
                t["active"] = False
                sell_price = t["tp_price"]
                gross_usdt = t["amount"] * sell_price * (1.0 - fee)
                profit_usdt = gross_usdt - t["cost_usdt"]
                
                avail_usdt += t["cost_usdt"]
                
                if profit_usdt > 0:
                    bought_btc = (profit_usdt * (1.0 - fee)) / sell_price
                    vault_btc += bought_btc
                trades += 1

        active_count = len([t for t in tranches if t["active"]])
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

    final_price = df["close"].iloc[-1]
    for t in tranches:
        if t["active"]:
            vault_btc += t["amount"]
    vault_btc += (avail_usdt / final_price)
    return vault_btc, trades

# ==============================================================================
# MODELO 3: GRID INVERTIDO ASIMÉTRICO CON BULL LOCKOUT
# ==============================================================================
def simulate_model_3_reverse_grid(df: pd.DataFrame, initial_btc: float = 1.0, fee: float = 0.001):
    btc = initial_btc
    pending_rebuys = []
    trades = 0

    for i in range(len(df)):
        price = df["close"].iloc[i]
        low = df["low"].iloc[i]
        atr = df["atr_14"].iloc[i]
        rsi = df["rsi_14"].iloc[i]
        dist = df["dist_ema_200"].iloc[i]

        for r in list(pending_rebuys):
            if low <= r["target_price"]:
                reacquired_btc = (r["usdt_amount"] * (1.0 - fee)) / r["target_price"]
                btc += reacquired_btc
                trades += 1
                pending_rebuys.remove(r)

        if dist < 1.05 and rsi > 68.0 and btc > 0.2:
            portion = btc * 0.15
            sell_proceeds = portion * price * (1.0 - fee)
            btc -= portion
            target_rebuy = price - (2.5 * atr)
            pending_rebuys.append({
                "usdt_amount": sell_proceeds,
                "target_price": target_rebuy
            })
            trades += 1

        if dist > 1.15 and pending_rebuys:
            for r in pending_rebuys:
                reacquired = (r["usdt_amount"] * (1.0 - fee)) / price
                btc += reacquired
            pending_rebuys.clear()

    final_price = df["close"].iloc[-1]
    for r in pending_rebuys:
        btc += (r["usdt_amount"] / final_price)
    return btc, trades

# ==============================================================================
# MODELO 4: ROTACIÓN DE FUERZA RELATIVA EN RATIO (Alt/BTC Multiplier)
# ==============================================================================
def simulate_model_4_ratio_rotation(df: pd.DataFrame, initial_btc: float = 1.0, fee: float = 0.001):
    btc = initial_btc
    kcs = 0.0
    trades = 0
    in_alt = False
    entry_ratio = 0.0

    for i in range(len(df)):
        ratio = df["kcs_btc_ratio"].iloc[i]
        ratio_rsi = df["ratio_rsi_daily"].iloc[i]

        # Entrada: capitulación en el ratio diario (RSI < 35)
        if not in_alt and ratio_rsi < 35.0 and btc > 0.3:
            alloc_btc = btc * 0.30
            kcs_bought = (alloc_btc * (1.0 - fee)) / ratio
            btc -= alloc_btc
            kcs += kcs_bought
            in_alt = True
            entry_ratio = ratio
            trades += 1

        # Salida: rebote del ratio a favor de la altcoin (ganancia > +20% o RSI > 62)
        elif in_alt:
            ratio_gain = (ratio / entry_ratio) - 1.0
            if ratio_rsi > 62.0 or ratio_gain > 0.20:
                btc_reacquired = (kcs * ratio) * (1.0 - fee)
                btc += btc_reacquired
                kcs = 0.0
                in_alt = False
                trades += 1

    final_ratio = df["kcs_btc_ratio"].iloc[-1]
    total_btc = btc + (kcs * final_ratio)
    return total_btc, trades

def main():
    print("==============================================================================")
    print("SIMULACIÓN CUANTITATIVA: 4 MODELOS PARA MAXIMIZAR SATOSHIS (2017 - 2026)")
    print("==============================================================================\n")
    
    df_raw = load_data_from_db()
    df = compute_indicators(df_raw)

    initial_btc = 1.0
    start_price = df["close"].iloc[0]
    final_price = df["close"].iloc[-1]
    
    print("\n3. Ejecutando backtest sobre 9 años de historia...", flush=True)

    bh_btc = 1.0
    bh_usd_end = bh_btc * final_price

    m1_btc, m1_trades = simulate_model_1_macro_rebalance(df, initial_btc=1.0)
    m2_btc, m2_trades = simulate_model_2_satoshi_leech(df, initial_btc=1.0, powder_usdt=2000.0)
    m3_btc, m3_trades = simulate_model_3_reverse_grid(df, initial_btc=1.0)
    m4_btc, m4_trades = simulate_model_4_ratio_rotation(df, initial_btc=1.0)

    table_data = [
        [
            "BENCHMARK: Buy & Hold",
            f"{bh_btc:.4f} BTC",
            "0.00%",
            f"${bh_usd_end:,.2f}",
            0,
            "Pasivo (100% exposición)"
        ],
        [
            "Modelo 1: Macro Dynamic Rebalance",
            f"{m1_btc:.4f} BTC",
            f"{((m1_btc / bh_btc) - 1.0) * 100:+.2f}%",
            f"${m1_btc * final_price:,.2f}",
            m1_trades,
            "Rotación en extremos de ciclo"
        ],
        [
            "Modelo 2: The Satoshi Leech (Harvest)",
            f"{m2_btc:.4f} BTC",
            f"{((m2_btc / bh_btc) - 1.0) * 100:+.2f}%",
            f"${m2_btc * final_price:,.2f}",
            m2_trades,
            "Bóveda intocable + obrero USDT"
        ],
        [
            "Modelo 3: Reverse Volatility Grid",
            f"{m3_btc:.4f} BTC",
            f"{((m3_btc / bh_btc) - 1.0) * 100:+.2f}%",
            f"${m3_btc * final_price:,.2f}",
            m3_trades,
            "Recompras por ATR con seguro Bull"
        ],
        [
            "Modelo 4: Ratio Rotation (Alt/BTC)",
            f"{m4_btc:.4f} BTC",
            f"{((m4_btc / bh_btc) - 1.0) * 100:+.2f}%",
            f"${m4_btc * final_price:,.2f}",
            m4_trades,
            "Arbitraje de ratio en capitulación"
        ],
    ]

    headers = [
        "Estrategia / Modelo",
        "BTC Final",
        "Alfa vs B&H (Sats)",
        "Valor USD Final",
        "Operaciones",
        "Mecánica Principal"
    ]

    print("\n" + tabulate(table_data, headers=headers, tablefmt="fancy_grid"))
    print(f"\n* Nota: Precio inicial BTC: ${start_price:,.2f} | Precio final BTC: ${final_price:,.2f}")
    print(f"* Periodo analizado: {df.index[0].strftime('%d-%b-%Y')} al {df.index[-1].strftime('%d-%b-%Y')} ({len(df):,} horas)")

if __name__ == "__main__":
    main()
