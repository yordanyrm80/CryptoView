import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

import psycopg2
import pandas as pd
import numpy as np
from tabulate import tabulate

from src.domain.models import BotConfig
from src.indicators.technical import TechnicalIndicators
from src.simulation.engine import SimulationEngine
from src.strategies.btc_quantum_evolution_regime import BtcQuantumEvolutionRegimeStrategy

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
    df_raw = pd.read_sql_query(query, conn)
    conn.close()

    df_raw["time"] = pd.to_datetime(df_raw["time"])
    df_raw["timestamp"] = (df_raw["time"].astype("int64") // 10**6)
    df_raw.set_index("time", inplace=True)

    df_full = TechnicalIndicators.apply_all(df_raw)
    start_filter = pd.Timestamp("2021-11-07 00:00:00", tz="UTC")
    df = df_full[df_full.index >= start_filter].copy()

    initial_capital = 2000.0

    config = BotConfig(
        bot_id="btc_evo_5y",
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

    metrics, equity_series, completed = engine.run(strategy, df, initial_capital=initial_capital)

    df_trades = pd.DataFrame([{
        "buy_date": pd.to_datetime(t.buy_timestamp, unit="ms", utc=True) if t.buy_timestamp else None,
        "sell_date": pd.to_datetime(t.sell_timestamp, unit="ms", utc=True) if t.sell_timestamp else None,
        "profit_usdt": t.profit_usdt,
        "tranche": t.tranche_index,
        "buy_price": t.buy_price,
        "sell_price": t.actual_sell_price
    } for t in completed])

    if not df_trades.empty:
        df_trades["year"] = df_trades["sell_date"].dt.year
        breakdown = df_trades.groupby("year").agg(
            trades=("profit_usdt", "count"),
            profit_total=("profit_usdt", "sum"),
            avg_profit=("profit_usdt", "mean")
        ).reset_index()

        print("\n" + "=" * 70)
        print("DESGLOSE DE OPERACIONES Y BENEFICIOS AÑO POR AÑO (2021 - 2026)")
        print("=" * 70)
        table_years = []
        for _, row in breakdown.iterrows():
            table_years.append([
                int(row["year"]),
                int(row["trades"]),
                f"${row['profit_total']:,.2f} USDT",
                f"${row['avg_profit']:,.2f} USDT"
            ])
        print(tabulate(table_years, headers=["Año", "Trades Cerrados", "Beneficio Total", "Promedio / Trade"], tablefmt="fancy_grid"))

    # Mostrar tramos que quedaron abiertos o atrapados
    print("\nEstado de los tramos al final de los 5 años:")
    for t in strategy.config.bot_id:
        pass

if __name__ == "__main__":
    main()
