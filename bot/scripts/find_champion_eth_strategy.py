import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import psycopg2
import pandas as pd
import numpy as np
from tabulate import tabulate

from src.domain.models import BotConfig
from src.indicators.technical import TechnicalIndicators
from src.simulation.engine import SimulationEngine
from src.strategies.btc_quantum_evolution_regime import BtcQuantumEvolutionRegimeStrategy

DB_URL = "postgresql://postgres:postgres@127.0.0.1:5432/CryptoViewPruebas"

def load_data():
    conn = psycopg2.connect(DB_URL)
    df_raw = pd.read_sql("SELECT time as dt, open, high, low, close, volume FROM candles_1h WHERE symbol = 'ETH/USDT' ORDER BY time ASC;", conn)
    conn.close()
    df_raw['dt'] = pd.to_datetime(df_raw['dt'], utc=True)
    df_raw.set_index('dt', inplace=True)
    df_raw['timestamp'] = df_raw.index.astype('int64') // 10**6
    return TechnicalIndicators.apply_all(df_raw)

def main():
    df = load_data()
    initial_capital = 1000.0

    print("==================================================================")
    print("BÚSQUEDA DE LA CALIBRACIÓN CAMPEONA PARA ETHEREUM (9 AÑOS)")
    print("==================================================================")

    # Variaciones a testear
    experiments = [
        # Baseline
        {
            "name": "1. Baseline BTC Champion (TP 4.5%, TS 1.4%, Trend 70%)",
            "tp": 4.5, "ts": 1.4, "trend_w": 0.70, "t0_rsi": 48.0, "panic_rsi": 28.0, "floor_w": 0.40,
            "weights": [0.30, 0.25, 0.20, 0.15, 0.10, 0.40, 0.35, 0.25],
        },
        # Fast Churning (TP 3.5% y 4.0%)
        {
            "name": "2. Alta Rotación (TP 3.8%, TS 1.4%, Trend 70%)",
            "tp": 3.8, "ts": 1.4, "trend_w": 0.70, "t0_rsi": 48.0, "panic_rsi": 28.0, "floor_w": 0.40,
            "weights": [0.30, 0.25, 0.20, 0.15, 0.10, 0.40, 0.35, 0.25],
        },
        {
            "name": "3. Alta Rotación (TP 3.5%, TS 1.4%, Trend 70%)",
            "tp": 3.5, "ts": 1.4, "trend_w": 0.70, "t0_rsi": 48.0, "panic_rsi": 28.0, "floor_w": 0.40,
            "weights": [0.30, 0.25, 0.20, 0.15, 0.10, 0.40, 0.35, 0.25],
        },
        # High Trend Capitalization (Trend 80% o 85%)
        {
            "name": "4. Trend Dominant (TP 4.5%, TS 1.4%, Trend 80%)",
            "tp": 4.5, "ts": 1.4, "trend_w": 0.80, "t0_rsi": 48.0, "panic_rsi": 28.0, "floor_w": 0.40,
            "weights": [0.30, 0.25, 0.20, 0.15, 0.10, 0.40, 0.35, 0.25],
        },
        {
            "name": "5. Trend Dominant (TP 4.5%, TS 1.4%, Trend 85%)",
            "tp": 4.5, "ts": 1.4, "trend_w": 0.85, "t0_rsi": 48.0, "panic_rsi": 28.0, "floor_w": 0.40,
            "weights": [0.30, 0.25, 0.20, 0.15, 0.10, 0.40, 0.35, 0.25],
        },
        # Floor Reinforcement (Piso reforzado al 50% de liquidez)
        {
            "name": "6. Suelo Reforzado (Floor 50%, TP 4.5%, Trend 75%)",
            "tp": 4.5, "ts": 1.4, "trend_w": 0.75, "t0_rsi": 48.0, "panic_rsi": 28.0, "floor_w": 0.50,
            "weights": [0.30, 0.25, 0.20, 0.15, 0.10, 0.50, 0.35, 0.25],
        },
        # Dynamic Mix: TP 4.0% + Trend 80% + Suelo 50%
        {
            "name": "7. Apex ETH Champion (TP 4.0%, Trend 80%, Suelo 50%)",
            "tp": 4.0, "ts": 1.4, "trend_w": 0.80, "t0_rsi": 48.0, "panic_rsi": 28.0, "floor_w": 0.50,
            "weights": [0.30, 0.25, 0.20, 0.15, 0.10, 0.50, 0.35, 0.25],
        },
        # Dynamic Mix 2: TP 4.2% + Trend 85% + Suelo 50%
        {
            "name": "8. Apex ETH Ultra (TP 4.2%, Trend 85%, Suelo 50%)",
            "tp": 4.2, "ts": 1.4, "trend_w": 0.85, "t0_rsi": 48.0, "panic_rsi": 28.0, "floor_w": 0.50,
            "weights": [0.30, 0.25, 0.20, 0.15, 0.10, 0.50, 0.35, 0.25],
        },
    ]

    results = []

    for exp in experiments:
        config = BotConfig(
            bot_id="eth_candidate",
            symbol="ETH/USDT",
            budget=initial_capital,
            take_profit_pct=exp["tp"],
            max_tranches=len(exp["weights"]),
            tranche_weights=exp["weights"],
            atr_multiplier=1.5,
            trailing_stop_pct=exp["ts"],
        )

        strat = BtcQuantumEvolutionRegimeStrategy(
            config=config,
            enable_compounding=True,
            trend_weight=exp["trend_w"],
            trailing_stop_pct=exp["ts"],
            t0_rsi_threshold=exp["t0_rsi"],
            panic_rsi_threshold=exp["panic_rsi"],
            floor_t5_weight=exp["floor_w"],
        )

        engine = SimulationEngine(
            fee_rate=0.001,
            stop_slippage=0.0005,
            enable_profit_recycling=True,
        )

        metrics, _, _ = engine.run(strat, df, initial_capital)

        results.append({
            "Configuración": exp["name"],
            "Capital Final": f"${metrics.final_equity:,.2f}",
            "Retorno Total": f"{metrics.total_return_pct:,.1f}%",
            "Max Drawdown": f"{metrics.max_drawdown_pct:.1f}%",
            "Trades": metrics.total_trades,
            "Win Rate": f"{metrics.win_rate_pct:.1f}%",
            "Sharpe": f"{metrics.sharpe_ratio:.2f}",
            "Profit Factor": f"{metrics.profit_factor:.2f}",
        })

    print("\n" + tabulate(results, headers="keys", tablefmt="github"))

if __name__ == "__main__":
    main()
