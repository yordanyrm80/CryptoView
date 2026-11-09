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

def load_data_last_4_years(symbol):
    conn = psycopg2.connect(DB_URL)
    # Rango de los últimos 4 años: 2022-11-09 a 2026-11-09
    query = f"""
        SELECT time as dt, open, high, low, close, volume 
        FROM candles_1h 
        WHERE symbol = '{symbol}' 
          AND time >= '2022-11-09 00:00:00+00'
        ORDER BY time ASC;
    """
    df = pd.read_sql(query, conn)
    conn.close()

    df['dt'] = pd.to_datetime(df['dt'], utc=True)
    df.set_index('dt', inplace=True)
    df['timestamp'] = df.index.astype('int64') // 10**6
    return TechnicalIndicators.apply_all(df)

def run_simulation(symbol, df, tp, ts, trend_w, floor_w, bot_id):
    initial_capital = 1000.0
    config = BotConfig(
        bot_id=bot_id,
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
    metrics, equity_curve, tranches = engine.run(strat, df, initial_capital)

    # Métricas de Buy & Hold del activo en el mismo periodo
    start_price = df['close'].iloc[0]
    end_price = df['close'].iloc[-1]
    bh_return_pct = ((end_price / start_price) - 1.0) * 100.0
    bh_final = initial_capital * (end_price / start_price)

    # Duración en años exactos
    total_days = (df.index[-1] - df.index[0]).total_seconds() / (24 * 3600)
    total_years = total_days / 365.25
    cagr = ((metrics.final_equity / initial_capital) ** (1.0 / total_years) - 1.0) * 100.0

    # Desglose año a año
    eq_df = pd.DataFrame({'equity': equity_curve})
    eq_df['year'] = eq_df.index.year
    annual = []
    prev = initial_capital
    for y in sorted(eq_df['year'].unique()):
        sub = eq_df[eq_df['year'] == y]
        end_eq = sub['equity'].iloc[-1]
        ret_y = ((end_eq / prev) - 1.0) * 100.0
        annual.append((y, end_eq, ret_y))
        prev = end_eq

    return {
        "symbol": symbol,
        "initial_capital": initial_capital,
        "final_equity": metrics.final_equity,
        "total_return_pct": metrics.total_return_pct,
        "cagr": cagr,
        "bh_start_price": start_price,
        "bh_end_price": end_price,
        "bh_return_pct": bh_return_pct,
        "bh_final": bh_final,
        "alpha_ratio": metrics.total_return_pct / bh_return_pct if bh_return_pct != 0 else 0,
        "trades": metrics.total_trades,
        "win_rate": metrics.win_rate_pct,
        "max_drawdown": metrics.max_drawdown_pct,
        "sharpe": metrics.sharpe_ratio,
        "profit_factor": metrics.profit_factor,
        "total_years": total_years,
        "candles": len(df),
        "annual": annual,
    }

def main():
    print("[1/3] Cargando velas horarias de los últimos 4 años (Nov 2022 - Nov 2026)...")
    df_btc = load_data_last_4_years("BTC/USDT")
    df_eth = load_data_last_4_years("ETH/USDT")

    print(f"      BTC velas: {len(df_btc):,} ({df_btc.index[0]} a {df_btc.index[-1]})")
    print(f"      ETH velas: {len(df_eth):,} ({df_eth.index[0]} a {df_eth.index[-1]})")

    print("[2/3] Ejecutando simulación para Apex Titan BTC Flagship...")
    res_btc = run_simulation("BTC/USDT", df_btc, tp=4.5, ts=1.4, trend_w=0.70, floor_w=0.40, bot_id="btc_4y")

    print("[3/3] Ejecutando simulación para Apex ETH Ultra...")
    res_eth = run_simulation("ETH/USDT", df_eth, tp=4.2, ts=1.4, trend_w=0.85, floor_w=0.50, bot_id="eth_4y")

    # Tabla 1: Comparativa Global a 4 Años
    summary = [
        ["Período Evaluado", f"{res_btc['total_years']:.2f} años (Nov 2022 - Nov 2026)", f"{res_eth['total_years']:.2f} años (Nov 2022 - Nov 2026)"],
        ["Velas Horarias", f"{res_btc['candles']:,} velas", f"{res_eth['candles']:,} velas"],
        ["Capital Inicial", f"${res_btc['initial_capital']:,.2f} USDT", f"${res_eth['initial_capital']:,.2f} USDT"],
        ["Capital Final Bot", f"${res_btc['final_equity']:,.2f} USDT", f"${res_eth['final_equity']:,.2f} USDT"],
        ["Retorno Total Bot", f"+{res_btc['total_return_pct']:,.1f}%", f"+{res_eth['total_return_pct']:,.1f}%"],
        ["CAGR (Promedio Anual Compuesto)", f"{res_btc['cagr']:.2f}% al año", f"{res_eth['cagr']:.2f}% al año"],
        ["Precio Inicial Activo", f"${res_btc['bh_start_price']:,.2f}", f"${res_eth['bh_start_price']:,.2f}"],
        ["Precio Final Activo", f"${res_btc['bh_end_price']:,.2f}", f"${res_eth['bh_end_price']:,.2f}"],
        ["Retorno Buy & Hold Activo", f"+{res_btc['bh_return_pct']:,.1f}% (${res_btc['bh_final']:,.2f})", f"+{res_eth['bh_return_pct']:,.1f}% (${res_eth['bh_final']:,.2f})"],
        ["Generación de Alfa (Bot vs Activo)", f"{res_btc['alpha_ratio']:.2f}x sobre Buy & Hold", f"{res_eth['alpha_ratio']:.2f}x sobre Buy & Hold"],
        ["Total Trades Ejecutados", f"{res_btc['trades']} trades", f"{res_eth['trades']} trades"],
        ["Win Rate (Trades Cerrados)", f"{res_btc['win_rate']:.1f}%", f"{res_eth['win_rate']:.1f}%"],
        ["Max Floating Drawdown", f"-{res_btc['max_drawdown']:.2f}%", f"-{res_eth['max_drawdown']:.2f}%"],
        ["Sharpe Ratio", f"{res_btc['sharpe']:.2f}", f"{res_eth['sharpe']:.2f}"],
        ["Profit Factor", f"{res_btc['profit_factor']:.2f}", f"{res_eth['profit_factor']:.2f}"],
    ]

    print("\n" + "=" * 95)
    print("      COMPARATIVA DIRECTA ÚLTIMOS 4 AÑOS: APEX TITAN BTC vs APEX ETH ULTRA")
    print("=" * 95)
    print(tabulate(summary, headers=["Métrica", "Apex Titan BTC Flagship", "Apex ETH Ultra"], tablefmt="github"))

    # Tabla 2: Comparativa Año a Año
    annual_table = []
    btc_dict = {a[0]: (a[1], a[2]) for a in res_btc['annual']}
    eth_dict = {a[0]: (a[1], a[2]) for a in res_eth['annual']}

    all_years = sorted(set(btc_dict.keys()).union(set(eth_dict.keys())))
    for y in all_years:
        b_end, b_ret = btc_dict.get(y, (0, 0))
        e_end, e_ret = eth_dict.get(y, (0, 0))
        annual_table.append([
            y,
            f"${b_end:,.2f}",
            f"{b_ret:+.1f}%",
            f"${e_end:,.2f}",
            f"{e_ret:+.1f}%"
        ])

    print("\n" + "=" * 80)
    print("      EVOLUCIÓN AÑO POR AÑO (ÚLTIMOS 4 AÑOS: 2022 - 2026)")
    print("=" * 80)
    print(tabulate(annual_table, headers=["Año", "BTC Cierre", "BTC Rend.", "ETH Cierre", "ETH Rend."], tablefmt="github"))

if __name__ == "__main__":
    main()
