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

from src.domain.models import BotConfig
from src.indicators.technical import TechnicalIndicators
from src.simulation.engine import SimulationEngine
from src.strategies.btc_quantum_compound_regime import BtcQuantumCompoundRegimeStrategy
from src.strategies.btc_quantum_evolution_regime import BtcQuantumEvolutionRegimeStrategy

DB_CONFIG = {
    "host": "127.0.0.1",
    "port": 5432,
    "user": "postgres",
    "password": "postgres",
    "dbname": "CryptoViewPruebas",
}

def load_data():
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
    # SimulationEngine expects integer millisecond timestamp in 'timestamp' column
    df["timestamp"] = (df["time"].astype("int64") // 10**6)
    df.set_index("time", inplace=True)
    return df

def main():
    print("==============================================================================")
    print("BENCHMARK OFICIAL DEFINITIVO: BOT OFICIAL USDT (APEX / EVOLUTION) VS RESTO")
    print("==============================================================================\n")
    print("1. Cargando 79,000+ velas de CryptoViewPruebas...", flush=True)
    df_raw = load_data()

    print("2. Calculando indicadores oficiales (EMA 50, EMA 200, Daily EMA 200, ATR, RSI, ADX)...", flush=True)
    df = TechnicalIndicators.apply_all(df_raw)

    initial_capital = 2000.0
    start_price = df["close"].iloc[0]
    final_price = df["close"].iloc[-1]

    # Motor oficial realista de KuCoin
    engine = SimulationEngine(
        fee_rate=0.001,
        stop_slippage=0.0005,
        enable_profit_recycling=True,
        allow_subsidized_discount=True,
        max_subsidized_discount_pct=0.12,
        recycle_profit_fraction=0.35,
        enable_cascading_discount=True,
    )

    print("3. Ejecutando BtcQuantumCompoundRegimeStrategy (Apex Flagship)...", flush=True)
    cfg_apex = BotConfig(
        bot_id="btc_apex_2k",
        symbol="BTC/USDT",
        budget=initial_capital,
        take_profit_pct=4.5,
        max_tranches=5,
        tranche_weights=[0.30, 0.25, 0.20, 0.15, 0.10],
        atr_multiplier=1.5,
        trailing_stop_pct=2.0,
    )
    strat_apex = BtcQuantumCompoundRegimeStrategy(
        config=cfg_apex,
        enable_compounding=True,
        trailing_stop_pct=2.0,
        panic_rsi_threshold=28.0,
    )
    m_apex, _, _ = engine.run(strat_apex, df, initial_capital=initial_capital)

    print("4. Ejecutando BtcQuantumEvolutionRegimeStrategy (Evolution Flagship)...", flush=True)
    cfg_evo = BotConfig(
        bot_id="btc_evo_2k",
        symbol="BTC/USDT",
        budget=initial_capital,
        take_profit_pct=4.5,
        max_tranches=8,
        tranche_weights=[0.30, 0.25, 0.20, 0.15, 0.10, 0.40, 0.35, 0.25],
        atr_multiplier=1.5,
        trailing_stop_pct=1.4,
    )
    strat_evo = BtcQuantumEvolutionRegimeStrategy(
        config=cfg_evo,
        enable_compounding=True,
        trend_weight=0.70,
        trailing_stop_pct=1.4,
        t0_rsi_threshold=48.0,
        panic_rsi_threshold=28.0,
        floor_t5_weight=0.40,
    )
    m_evo, _, _ = engine.run(strat_evo, df, initial_capital=initial_capital)

    # Conversión a BTC al precio de corte ($75,822)
    btc_apex = m_apex.final_equity / final_price
    btc_evo = m_evo.final_equity / final_price

    # Buy & Hold
    bh_btc = (initial_capital * 0.999) / start_price
    bh_usd = bh_btc * final_price

    # Satoshi Leech (del script previo)
    leech_btc = 0.3054
    leech_usd = leech_btc * final_price

    # Crash Accumulator (25% en caídas, del script previo)
    crash_btc = 0.2491
    crash_usd = crash_btc * final_price

    table_data = [
        [
            "1. BOT EVOLUTION (Oficial USDT Flagship)",
            f"${m_evo.final_equity:,.2f} USDT",
            f"{btc_evo:.4f} BTC",
            f"{((btc_evo / bh_btc) - 1.0) * 100:+.2f}%",
            m_evo.total_trades,
            f"{m_evo.win_rate_pct:.1f}%",
            "Compounding geométrico + 35% subsidio cascada"
        ],
        [
            "2. BOT APEX (Oficial USDT Compound)",
            f"${m_apex.final_equity:,.2f} USDT",
            f"{btc_apex:.4f} BTC",
            f"{((btc_apex / bh_btc) - 1.0) * 100:+.2f}%",
            m_apex.total_trades,
            f"{m_apex.win_rate_pct:.1f}%",
            "Front-loaded [30,25,20,15,10] + Sniper"
        ],
        [
            "3. BUY & HOLD ($2,000 BTC en 2017)",
            f"${bh_usd:,.2f} USD",
            f"{bh_btc:.4f} BTC",
            "0.00%",
            0,
            "N/A",
            "Comprado a $4,950 en 2017 (100% pasivo)"
        ],
        [
            "4. SATOSHI LEECH (Cosecha Fija a BTC)",
            f"${leech_usd:,.2f} USD",
            f"{leech_btc:.4f} BTC",
            f"{((leech_btc / bh_btc) - 1.0) * 100:+.2f}%",
            176,
            "100.0%",
            "Cosecha satoshis a coste cero sin compounding"
        ],
        [
            "5. BOT USDT + COMPRA EN CAÍDAS (25%)",
            f"${crash_usd:,.2f} USD",
            f"{crash_btc:.4f} BTC",
            f"{((crash_btc / bh_btc) - 1.0) * 100:+.2f}%",
            4,
            "100.0%",
            "Compra BTC en capitulaciones (sin subsidio)"
        ],
    ]

    headers = [
        "Estrategia (Todas con $2,000 USDT de inicio)",
        "Valor Final en USD",
        "Bitcoins Finales Conseguidos",
        "Alfa vs B&H (Sats)",
        "Trades",
        "Win Rate",
        "Mecánica Principal"
    ]

    print("\n" + tabulate(table_data, headers=headers, tablefmt="fancy_grid"))
    print(f"\n* Periodo analizado: {df.index[0].strftime('%d-%b-%Y')} al {df.index[-1].strftime('%d-%b-%Y')} ({len(df):,} horas)")
    print(f"* Precio inicial BTC: ${start_price:,.2f} | Precio final BTC: ${final_price:,.2f}")

if __name__ == "__main__":
    main()
