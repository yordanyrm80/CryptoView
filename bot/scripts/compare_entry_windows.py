import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

import psycopg2
import pandas as pd
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

    engine = SimulationEngine(
        fee_rate=0.001,
        stop_slippage=0.0005,
        enable_profit_recycling=True,
        allow_subsidized_discount=True,
        max_subsidized_discount_pct=0.12,
        recycle_profit_fraction=0.35,
        enable_cascading_discount=True,
    )

    windows = {
        "1. Techo Histórico (Nov 2021 a Nov 2026 - 5 años)": "2021-11-07",
        "2. Fondo del Crash (Nov 2022 a Nov 2026 - 4 años)": "2022-11-07",
        "3. Inicio Ciclo Alcista (Ene 2023 a Nov 2026 - ~4 años)": "2023-01-01",
        "4. Mitad del Ciclo (Ene 2024 a Nov 2026 - ~3 años)": "2024-01-01",
    }

    results = []
    initial_cap = 2000.0

    for name, start_date in windows.items():
        sub_df = df_full[df_full.index >= pd.Timestamp(start_date, tz="UTC")].copy()
        start_p = sub_df["close"].iloc[0]
        end_p = sub_df["close"].iloc[-1]

        cfg = BotConfig(
            bot_id="evo_test",
            symbol="BTC/USDT",
            budget=initial_cap,
            take_profit_pct=4.5,
            max_tranches=8,
            tranche_weights=[0.30, 0.25, 0.20, 0.15, 0.10, 0.40, 0.35, 0.25],
            atr_multiplier=1.5,
            trailing_stop_pct=1.4,
        )
        strat = BtcQuantumEvolutionRegimeStrategy(
            config=cfg,
            enable_compounding=True,
            trend_weight=0.70,
            trailing_stop_pct=1.4,
            t0_rsi_threshold=48.0,
            panic_rsi_threshold=28.0,
            floor_t5_weight=0.40,
        )

        m, _, _ = engine.run(strat, sub_df, initial_capital=initial_cap)
        bh_pct = ((end_p / start_p) - 1.0) * 100.0
        bh_usd = initial_cap * (1.0 + (bh_pct / 100.0))

        results.append([
            name,
            f"${start_p:,.0f} -> ${end_p:,.0f}",
            f"${m.final_equity:,.2f} ({m.total_return_pct:+,.1f}%)",
            f"${bh_usd:,.2f} ({bh_pct:+,.1f}%)",
            f"${m.cash_flow_usdt:,.2f}",
            m.total_trades,
            f"-{m.max_drawdown_pct:.1f}%"
        ])

    headers = [
        "Ventana de Entrada",
        "Precio BTC (Inicio -> Fin)",
        "Bot Evolution Final",
        "Buy & Hold Final",
        "Cash Extraído",
        "Trades",
        "Max DD"
    ]

    print("\n" + "=" * 90)
    print("SENSIBILIDAD AL TIMING DE ENTRADA: ¿POR QUÉ IMPORTA EL PUNTO DE PARTIDA?")
    print("=" * 90)
    print(tabulate(results, headers=headers, tablefmt="fancy_grid"))

if __name__ == "__main__":
    main()
