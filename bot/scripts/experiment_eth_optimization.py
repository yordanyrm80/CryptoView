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

def load_eth_1h_candles():
    print("[1/3] Cargando 79,234 velas horarias de ETH/USDT desde CryptoViewPruebas...")
    conn = psycopg2.connect(DB_URL)
    query = """
        SELECT time as dt, open, high, low, close, volume 
        FROM candles_1h 
        WHERE symbol = 'ETH/USDT' 
        ORDER BY time ASC;
    """
    df = pd.read_sql(query, conn)
    conn.close()

    df['dt'] = pd.to_datetime(df['dt'], utc=True)
    df.set_index('dt', inplace=True)
    df['timestamp'] = df.index.astype('int64') // 10**6
    print(f"      Velas cargadas: {len(df):,} ({df.index[0].date()} a {df.index[-1].date()})")
    return df

def run_eth_experiments():
    df_raw = load_eth_1h_candles()

    print("[2/3] Calculando indicadores técnicos sobre las 79,234 velas de ETH...")
    df = TechnicalIndicators.apply_all(df_raw)

    print("[3/3] Ejecutando suite de experimentos paramétricos para ETH...")
    initial_capital = 1000.0

    # Definir experimentos a probar
    experiments = [
        # 1. Línea Base (BTC Champion directo en ETH)
        {
            "name": "1. Línea Base (Parámetros BTC)",
            "tp": 4.5, "ts": 1.4, "trend_w": 0.70, "t0_rsi": 48.0, "panic_rsi": 28.0,
            "weights": [0.30, 0.25, 0.20, 0.15, 0.10, 0.40, 0.35, 0.25],
            "harvest_mode": "USDT", "satoshi": False,
        },
        # 2. TP ampliado (5.5% y 6.5%) con Trailing Stop adaptado (2.2%)
        {
            "name": "2. TP 5.5% + Trailing 2.0%",
            "tp": 5.5, "ts": 2.0, "trend_w": 0.70, "t0_rsi": 48.0, "panic_rsi": 28.0,
            "weights": [0.30, 0.25, 0.20, 0.15, 0.10, 0.40, 0.35, 0.25],
            "harvest_mode": "USDT", "satoshi": False,
        },
        {
            "name": "3. TP 6.5% + Trailing 2.5%",
            "tp": 6.5, "ts": 2.5, "trend_w": 0.70, "t0_rsi": 48.0, "panic_rsi": 28.0,
            "weights": [0.30, 0.25, 0.20, 0.15, 0.10, 0.40, 0.35, 0.25],
            "harvest_mode": "USDT", "satoshi": False,
        },
        {
            "name": "4. TP 8.0% + Trailing 2.8%",
            "tp": 8.0, "ts": 2.8, "trend_w": 0.70, "t0_rsi": 48.0, "panic_rsi": 28.0,
            "weights": [0.30, 0.25, 0.20, 0.15, 0.10, 0.40, 0.35, 0.25],
            "harvest_mode": "USDT", "satoshi": False,
        },
        # 3. Pesos balanceados (defensa ante caídas profundas de ETH)
        {
            "name": "5. Pesos Planos [20/20/20/20/20%] + TP 6.0%",
            "tp": 6.0, "ts": 2.2, "trend_w": 0.70, "t0_rsi": 48.0, "panic_rsi": 28.0,
            "weights": [0.20, 0.20, 0.20, 0.20, 0.20, 0.40, 0.35, 0.25],
            "harvest_mode": "USDT", "satoshi": False,
        },
        {
            "name": "6. Pesos Defensivos [15/20/25/25/15%] + TP 6.5%",
            "tp": 6.5, "ts": 2.4, "trend_w": 0.70, "t0_rsi": 48.0, "panic_rsi": 28.0,
            "weights": [0.15, 0.20, 0.25, 0.25, 0.15, 0.40, 0.35, 0.25],
            "harvest_mode": "USDT", "satoshi": False,
        },
        # 4. Filtro de Pánico más estricto (RSI 24 en vez de 28)
        {
            "name": "7. Pánico Estricto (RSI 24) + TP 6.5%",
            "tp": 6.5, "ts": 2.2, "trend_w": 0.70, "t0_rsi": 45.0, "panic_rsi": 24.0,
            "weights": [0.25, 0.25, 0.20, 0.15, 0.15, 0.40, 0.35, 0.25],
            "harvest_mode": "USDT", "satoshi": False,
        },
        # 5. Acumulación pura en ETH (Ether Accumulator)
        {
            "name": "8. Ether Accumulator (Cosecha en ETH)",
            "tp": 5.5, "ts": 2.0, "trend_w": 0.70, "t0_rsi": 48.0, "panic_rsi": 28.0,
            "weights": [0.30, 0.25, 0.20, 0.15, 0.10, 0.40, 0.35, 0.25],
            "harvest_mode": "CRYPTO", "satoshi": True,
        },
    ]

    results = []

    for exp in experiments:
        config = BotConfig(
            bot_id=f"eth_sim_{exp['tp']}",
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
            floor_t5_weight=exp["weights"][5] if len(exp["weights"]) > 5 else 0.40,
        )

        engine = SimulationEngine(
            fee_rate=0.001,
            stop_slippage=0.0005,
            enable_profit_recycling=True,
            harvest_mode=exp["harvest_mode"],
            satoshi_recycling=exp["satoshi"],
        )

        metrics, equity_curve, tranches = engine.run(strat, df, initial_capital)

        # Buy & Hold return
        bh_pct = (df['close'].iloc[-1] / df['close'].iloc[0] - 1) * 100

        results.append({
            "Experimento": exp["name"],
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
    run_eth_experiments()
