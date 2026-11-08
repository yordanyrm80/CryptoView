import sys
import os
from pathlib import Path
from datetime import datetime, timezone

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

import psycopg2
import pandas as pd
import numpy as np
from tabulate import tabulate

from src.indicators.technical import TechnicalIndicators
from src.domain.models import BotConfig
from src.strategies.btc_quantum_evolution_regime import BtcQuantumEvolutionRegimeStrategy
from src.simulation.engine import SimulationEngine

DB_CONFIG = {
    "host": "127.0.0.1",
    "port": 5432,
    "user": "postgres",
    "password": "postgres",
    "dbname": "CryptoViewPruebas",
}

def load_candles_with_radar():
    conn = psycopg2.connect(**DB_CONFIG)
    query = """
    SELECT "time", open, high, low, close, volume 
    FROM public.candles_1h 
    WHERE symbol = 'BTC/USDT' 
    ORDER BY "time" ASC;
    """
    df_raw = pd.read_sql_query(query, conn)
    conn.close()

    df_raw["time"] = pd.to_datetime(df_raw["time"])
    df_raw["timestamp"] = (df_raw["time"].astype("int64") // 10**6)
    df_raw.set_index("time", inplace=True)

    # Indicadores técnicos base
    df = TechnicalIndicators.apply_all(df_raw)
    
    # 1. ATH acumulado y drawdown desde ATH
    df["ath"] = df["close"].cummax()
    df["drawdown_from_ath"] = (df["close"] - df["ath"]) / df["ath"]
    
    # 2. RSI Diario aproximado (span = 14 * 24 horas = 336h)
    delta = df["close"].diff()
    gain = delta.where(delta > 0, 0.0)
    loss = -delta.where(delta < 0, 0.0)
    avg_gain = gain.ewm(alpha=1.0 / (14 * 24), adjust=False).mean()
    avg_loss = loss.ewm(alpha=1.0 / (14 * 24), adjust=False).mean()
    rs = avg_gain / avg_loss.replace(0, np.nan)
    df["rsi_daily"] = (100.0 - (100.0 / (1.0 + rs))).fillna(50.0)
    
    # 3. Distancia porcentual a la EMA 200 Diaria (4800 horas)
    df["dist_ema_200_daily"] = (df["close"] - df["ema_daily_200"]) / df["ema_daily_200"]
    
    # 4. Días bajo la EMA 200 diaria (para saber si viene de un mercado bajista)
    df["below_ema_200"] = (df["close"] < df["ema_daily_200"]).astype(int)
    
    return df

def run_simulation(df_slice: pd.DataFrame, initial_capital: float = 2000.0):
    config = BotConfig(
        bot_id="radar_bot",
        symbol="BTC/USDT",
        budget=initial_capital,
        take_profit_pct=4.5,
        max_tranches=8,
        tranche_weights=[0.30, 0.25, 0.20, 0.15, 0.10, 0.40, 0.35, 0.25],
        atr_multiplier=1.5,
        trailing_stop_pct=1.4,
    )
    strategy = BtcQuantumEvolutionRegimeStrategy(
        config=config,
        enable_compounding=True,
        trend_weight=0.70,
        trailing_stop_pct=1.4,
        t0_rsi_threshold=48.0,
        panic_rsi_threshold=28.0,
        floor_t5_weight=0.40,
    )
    engine = SimulationEngine(
        fee_rate=0.001,
        stop_slippage=0.0005,
        enable_profit_recycling=True,
        allow_subsidized_discount=True,
        max_subsidized_discount_pct=0.12,
        recycle_profit_fraction=0.35,
        enable_cascading_discount=True,
    )
    metrics, equity_series, completed = engine.run(strategy, df_slice, initial_capital=initial_capital)
    return metrics

def evaluate_moment(df: pd.DataFrame, name: str, category: str, start_dt_str: str):
    start_dt = pd.Timestamp(start_dt_str, tz="UTC")
    if start_dt not in df.index:
        # Encontrar el índice más cercano
        pos = df.index.get_indexer([start_dt], method='nearest')[0]
        start_dt = df.index[pos]
    
    idx_pos = df.index.get_loc(start_dt)
    start_price = df.iloc[idx_pos]["close"]
    
    # Evaluar ventana 1 año (365 días * 24 horas = 8760 velas)
    hours_1y = 365 * 24
    hours_2y = 730 * 24
    
    slice_1y = df.iloc[idx_pos: min(len(df), idx_pos + hours_1y)].copy()
    slice_2y = df.iloc[idx_pos: min(len(df), idx_pos + hours_2y)].copy()
    slice_full = df.iloc[idx_pos:].copy()
    
    m_1y = run_simulation(slice_1y)
    m_2y = run_simulation(slice_2y) if len(slice_2y) > hours_1y else None
    m_full = run_simulation(slice_full)
    
    bnh_1y = ((slice_1y.iloc[-1]["close"] - start_price) / start_price) * 100.0
    bnh_full = ((slice_full.iloc[-1]["close"] - start_price) / start_price) * 100.0
    
    return {
        "name": name,
        "category": category,
        "start_date": str(start_dt.date()),
        "start_price": f"${start_price:,.0f}",
        # 1 Año
        "ret_1y": f"{m_1y.total_return_pct:+.1f}%",
        "cash_1y": f"${m_1y.cash_flow_usdt:,.0f}",
        "dd_1y": f"{m_1y.max_drawdown_pct:.1f}%",
        "trapped_1y": f"{m_1y.max_days_trapped:.0f}d",
        "bnh_1y": f"{bnh_1y:+.1f}%",
        # 2 Años
        "ret_2y": f"{m_2y.total_return_pct:+.1f}%" if m_2y else "N/A",
        "cash_2y": f"${m_2y.cash_flow_usdt:,.0f}" if m_2y else "N/A",
        # Full (Hasta 2026)
        "equity_full": f"${m_full.final_equity:,.0f}",
        "cash_full": f"${m_full.cash_flow_usdt:,.0f}",
        "trades_full": m_full.total_trades,
    }

def main():
    print("Cargando 9 años de velas horarias y calculando indicadores macro...")
    df = load_candles_with_radar()
    print(f"Total velas cargadas: {len(df)} (Desde {df.index[0]} hasta {df.index[-1]})")
    
    # Definimos los puntos históricos clave de cada arquetipo para simularlos
    test_cases = [
        # --- ARQUETIPO 1: VENTANA DORADA (Ruptura EMA 200 Diaria con RSI sano) ---
        ("Ruptura Ciclo 2019", "Ventana Dorada", "2019-04-02 00:00:00"),
        ("Ruptura Post-COVID 2020", "Ventana Dorada", "2020-04-29 00:00:00"),
        ("Ruptura Salida FTX 2023", "Ventana Dorada", "2023-10-23 00:00:00"),
        
        # --- ARQUETIPO 2: POZO DE CAPITULACIÓN (Caída > 65% + RSI < 28) ---
        ("Suelo Invierno 2018", "Pozo Capitulación", "2018-12-16 00:00:00"),
        ("Crash Pánico COVID 2020", "Pozo Capitulación", "2020-03-13 00:00:00"),
        ("Suelo Colapso FTX 2022", "Pozo Capitulación", "2022-11-21 00:00:00"),
        
        # --- ARQUETIPO 3: COMPRESIÓN POST-HALVING (90 - 150 días post-halving) ---
        ("Post-Halving 2020 (Mes 5)", "Post-Halving Squeeze", "2020-10-10 00:00:00"),
        ("Post-Halving 2024 (Mes 4)", "Post-Halving Squeeze", "2024-08-20 00:00:00"),
        
        # --- GRUPO CONTROL: ZONA ROJA / EUFORIA (Techo parabólico, NO LANZAR) ---
        ("Pico Burbuja 2017", "Zona Roja (Peligro)", "2017-12-16 00:00:00"),
        ("Pico Coinbase IPO 2021", "Zona Roja (Peligro)", "2021-04-14 00:00:00"),
        ("Pico ATH Noviembre 2021", "Zona Roja (Peligro)", "2021-11-08 00:00:00"),
    ]
    
    results = []
    print("\nEjecutando simulaciones comparativas de lanzamiento de bot...")
    for name, cat, dt_str in test_cases:
        print(f" -> Evaluando: {name} ({cat}) el {dt_str[:10]}...")
        res = evaluate_moment(df, name, cat, dt_str)
        results.append(res)
        
    # Presentar tabla a 1 Año
    headers_1y = ["Evento de Entrada", "Arquetipo", "Fecha", "Precio BTC", "Retorno 1 Año", "Cash 1 Año", "Max DD 1A", "Días Atrapado", "Buy & Hold 1A"]
    table_1y = [
        [r["name"], r["category"], r["start_date"], r["start_price"], r["ret_1y"], r["cash_1y"], r["dd_1y"], r["trapped_1y"], r["bnh_1y"]]
        for r in results
    ]
    
    print("\n" + "=" * 110)
    print("TABLA COMPARATIVA: RENDIMIENTO DEL BOT A 1 AÑO SEGÚN EL MOMENTO DE ENTRADA (Capital $2,000)")
    print("=" * 110)
    print(tabulate(table_1y, headers=headers_1y, tablefmt="fancy_grid"))
    
    # Presentar tabla a 2 Años y Total
    headers_full = ["Evento de Entrada", "Arquetipo", "Fecha", "Retorno 2 Años", "Cash 2 Años", "Equidad Final (Nov 2026)", "Cash Total Extraído", "Trades"]
    table_full = [
        [r["name"], r["category"], r["start_date"], r["ret_2y"], r["cash_2y"], r["equity_full"], r["cash_full"], r["trades_full"]]
        for r in results
    ]
    
    print("\n" + "=" * 110)
    print("TABLA COMPARATIVA: RENDIMIENTO DEL BOT A 2 AÑOS Y PATRIMONIO TOTAL HASTA 2026 (Capital $2,000)")
    print("=" * 110)
    print(tabulate(table_full, headers=headers_full, tablefmt="fancy_grid"))

if __name__ == "__main__":
    main()
