import sys
import os
from pathlib import Path

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

def load_candles():
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

    df = TechnicalIndicators.apply_all(df_raw)
    
    # 1. Pi Cycle Top Indicator
    df["sma_111d"] = df["close"].rolling(111 * 24).mean()
    df["sma_350d_x2"] = df["close"].rolling(350 * 24).mean() * 2.0
    df["pi_cycle_cross"] = (df["sma_111d"] >= df["sma_350d_x2"]).astype(int)
    df["pi_cycle_signal"] = (df["pi_cycle_cross"] == 1) & (df["pi_cycle_cross"].shift(1) == 0)
    
    # 2. Daily EMA 50 (50 * 24h = 1200h)
    df["ema_daily_50"] = df["close"].ewm(span=50 * 24, adjust=False).mean()
    
    # 3. ATH acumulado
    df["ath"] = df["close"].cummax()
    
    # 4. Señal de Ruptura Estructural de Techo (Structural Breakdown):
    # Condición: El precio estuvo a menos del 5% del ATH, y luego pierde la Daily EMA 50 con caída > 12% desde el pico
    df["dist_from_ath"] = (df["close"] - df["ath"]) / df["ath"]
    df["lost_ema_50"] = (df["close"] < df["ema_daily_50"]) & (df["close"].shift(24) >= df["ema_daily_50"].shift(24))
    
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
    return metrics, equity_series

def main():
    print("Cargando datos y analizando señales de salida macro...")
    df = load_candles()
    
    # Analicemos los dos grandes techos de 2021:
    # 1. Alerta Pi Cycle Top: 2021-04-12 @ $59,963
    # 2. Pérdida estructural en el 2do pico: 2021-11-18 @ $56,900
    
    exit_events = [
        ("Techo 1 (Pi Cycle Top)", "2021-04-12 00:00:00", "2022-11-21 21:00:00"), # Hasta el suelo de FTX
        ("Techo 2 (Ruptura Estructural)", "2021-11-18 00:00:00", "2022-11-21 21:00:00"),
    ]
    
    table = []
    for name, start_str, end_str in exit_events:
        start_dt = pd.Timestamp(start_str, tz="UTC")
        end_dt = pd.Timestamp(end_str, tz="UTC")
        
        slice_bear = df.loc[start_dt:end_dt].copy()
        start_price = slice_bear.iloc[0]["close"]
        end_price = slice_bear.iloc[-1]["close"]
        
        # Correr el bot normal a través de todo el invierno sin salirse
        m, eq = run_simulation(slice_bear, 2000.0)
        
        # Si el bot se hubiese quedado 100% en USDT líquido en la alerta:
        # Tendría $2,000 intactos. Y en el suelo ($15.5k), con esos $2,000 compra:
        btc_bought_at_bottom_with_cash = 2000.0 / end_price
        
        # Pero con el bot activo sin salirse:
        bot_final_equity = m.final_equity
        bot_cash_extracted = m.cash_flow_usdt
        
        # Si con la equidad final del bot se compra BTC en el suelo:
        btc_bought_by_bot = (bot_final_equity + bot_cash_extracted) / end_price
        
        bnh_loss = ((end_price - start_price) / start_price) * 100.0
        bot_loss = ((bot_final_equity - 2000.0) / 2000.0) * 100.0
        
        table.append([
            name,
            str(start_dt.date()),
            f"${start_price:,.0f}",
            f"${end_price:,.0f} ({bnh_loss:.1f}%)",
            f"${bot_final_equity:,.0f} ({bot_loss:.1f}%)",
            f"${bot_cash_extracted:,.0f}",
            f"{btc_bought_at_bottom_with_cash:.4f} BTC",
            f"{btc_bought_by_bot:.4f} BTC"
        ])
        
    print("\n" + "=" * 115)
    print("COMPARATIVA DE SALIDA MACRO: QUEDARSE EN USDT EN LA ALERTA VS MANTENER EL BOT ACTIVO EN EL INVIERNO")
    print("=" * 115)
    headers = [
        "Alerta de Techo", 
        "Fecha Alerta", 
        "Precio Salida", 
        "Suelo Final (B&H)", 
        "Equidad Bot en Suelo", 
        "Cash Extraído Bot", 
        "BTC Comprable si Sales a USDT", 
        "BTC Comprable si Mantienes Bot"
    ]
    print(tabulate(table, headers=headers, tablefmt="fancy_grid"))

if __name__ == "__main__":
    main()
