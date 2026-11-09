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

def get_annual_breakdown(symbol, tp, ts, trend_w, floor_w):
    conn = psycopg2.connect(DB_URL)
    df_raw = pd.read_sql(f"SELECT time as dt, open, high, low, close, volume FROM candles_1h WHERE symbol = '{symbol}' ORDER BY time ASC;", conn)
    conn.close()
    df_raw['dt'] = pd.to_datetime(df_raw['dt'], utc=True)
    df_raw.set_index('dt', inplace=True)
    df_raw['timestamp'] = df_raw.index.astype('int64') // 10**6
    df = TechnicalIndicators.apply_all(df_raw)

    initial_capital = 1000.0
    config = BotConfig(
        bot_id=f"annual_calc_{symbol.replace('/', '_')}",
        symbol=symbol,
        budget=initial_capital,
        take_profit_pct=tp,
        max_tranches=8,
        tranche_weights=[0.30, 0.25, 0.20, 0.15, 0.10, floor_w, 0.35, 0.25],
        atr_multiplier=1.5,
        trailing_stop_pct=ts,
    )
    strat = BtcQuantumEvolutionRegimeStrategy(
        config=config,
        enable_compounding=True,
        trend_weight=trend_w,
        trailing_stop_pct=ts,
        t0_rsi_threshold=48.0,
        panic_rsi_threshold=28.0,
        floor_t5_weight=floor_w,
    )
    engine = SimulationEngine(fee_rate=0.001, stop_slippage=0.0005, enable_profit_recycling=True)
    metrics, equity_curve, _ = engine.run(strat, df, initial_capital)

    # Agrupar equity por año
    equity_df = pd.DataFrame({'equity': equity_curve})
    equity_df['year'] = equity_df.index.year

    years = sorted(equity_df['year'].unique())
    annual_results = []
    
    prev_eq = initial_capital
    for y in years:
        sub = equity_df[equity_df['year'] == y]
        end_eq = sub['equity'].iloc[-1]
        year_return = ((end_eq / prev_eq) - 1) * 100
        annual_results.append({
            "Año": y,
            "Capital Cierre": f"${end_eq:,.2f}",
            "Rendimiento Anual": f"{year_return:+.1f}%"
        })
        prev_eq = end_eq

    # Cálculo exacto de CAGR
    total_days = (df.index[-1] - df.index[0]).total_seconds() / (24 * 3600)
    total_years = total_days / 365.25
    cagr = ((metrics.final_equity / initial_capital) ** (1.0 / total_years) - 1.0) * 100.0

    return metrics.final_equity, metrics.total_return_pct, cagr, total_years, annual_results

def main():
    print("Calculando rendimiento anual para BTC Flagship y ETH Ultra...")
    btc_final, btc_ret, btc_cagr, years, btc_annual = get_annual_breakdown("BTC/USDT", 4.5, 1.4, 0.70, 0.40)
    eth_final, eth_ret, eth_cagr, _, eth_annual = get_annual_breakdown("ETH/USDT", 4.2, 1.4, 0.85, 0.50)

    print("\n==================================================================")
    print("RESUMEN DE RENDIMIENTO ANUAL Y CAGR (2017 - 2026)")
    print("==================================================================")
    print(f"Período evaluado: {years:.2f} años ininterrumpidos")
    print(f"Capital inicial:  $1,000.00 USDT\n")
    print(f"1. BITCOIN (Apex Titan BTC Flagship):")
    print(f"   - Capital Final:  ${btc_final:,.2f}")
    print(f"   - Retorno Total:  {btc_ret:,.1f}%")
    print(f"   - CAGR (Promedio Compuesto Anual): {btc_cagr:.2f}% al año\n")

    print(f"2. ETHEREUM (Apex Titan ETH Ultra):")
    print(f"   - Capital Final:  ${eth_final:,.2f}")
    print(f"   - Retorno Total:  {eth_ret:,.1f}%")
    print(f"   - CAGR (Promedio Compuesto Anual): {eth_cagr:.2f}% al año\n")

    # Tabla comparativa año por año
    combined = []
    for b, e in zip(btc_annual, eth_annual):
        combined.append({
            "Año": b["Año"],
            "BTC Cierre": b["Capital Cierre"],
            "BTC Rend.": b["Rendimiento Anual"],
            "ETH Cierre": e["Capital Cierre"],
            "ETH Rend.": e["Rendimiento Anual"]
        })

    print(tabulate(combined, headers="keys", tablefmt="github"))

if __name__ == "__main__":
    main()
