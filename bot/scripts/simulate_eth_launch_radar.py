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

    df = TechnicalIndicators.apply_all(df_raw)
    
    # Calcular Daily ATH Drawdown sobre ETH
    df['ath'] = df['close'].cummax()
    df['drawdown_from_ath'] = ((df['close'] - df['ath']) / df['ath']) * 100.0

    # Indicadores diarios aproximados en 1h
    df['dist_ema_daily_200_pct'] = ((df['close'] - df['ema_daily_200']) / df['ema_daily_200']) * 100.0
    return df

def test_archetype(df, start_dates, label):
    initial_capital = 1000.0
    results = []

    for dt_str in start_dates:
        start_ts = pd.to_datetime(dt_str, utc=True)
        # Buscar el punto más cercano
        sub_df = df.loc[start_ts:]
        if len(sub_df) < 24 * 30: # mínimo 1 mes
            continue

        # Simular 1 año (8,760 velas) o hasta el final
        eval_df = sub_df.iloc[:min(len(sub_df), 8760)]
        start_price = eval_df['close'].iloc[0]
        end_price = eval_df['close'].iloc[-1]
        bh_ret = ((end_price / start_price) - 1.0) * 100.0

        config = BotConfig(
            bot_id=f"eth_radar_{dt_str}",
            symbol="ETH/USDT",
            budget=initial_capital,
            take_profit_pct=4.2,
            max_tranches=8,
            tranche_weights=[0.30, 0.25, 0.20, 0.15, 0.10, 0.50, 0.35, 0.25],
            atr_multiplier=1.5,
            trailing_stop_pct=1.4,
        )
        strat = BtcQuantumEvolutionRegimeStrategy(
            config=config,
            enable_compounding=True,
            trend_weight=0.85,
            trailing_stop_pct=1.4,
            t0_rsi_threshold=48.0,
            panic_rsi_threshold=28.0,
            floor_t5_weight=0.50,
        )
        engine = SimulationEngine(fee_rate=0.001, stop_slippage=0.0005, enable_profit_recycling=True)
        metrics, equity_curve, tranches = engine.run(strat, eval_df, initial_capital)

        # Medir días de estancamiento (días donde equity estuvo por debajo del 85% del capital inicial)
        underwater = (equity_curve < initial_capital * 0.85)
        trapped_days = (underwater.sum() / 24.0)

        results.append({
            "Fecha Entrada": dt_str,
            "Precio ETH": f"${start_price:,.2f}",
            "Retorno Bot (1 Año)": metrics.total_return_pct,
            "Retorno B&H (1 Año)": bh_ret,
            "Max Drawdown": metrics.max_drawdown_pct,
            "Días Atrapado": trapped_days,
            "Trades": metrics.total_trades,
            "Win Rate": metrics.win_rate_pct,
        })

    if not results:
        return None

    res_df = pd.DataFrame(results)
    avg_bot_ret = res_df["Retorno Bot (1 Año)"].mean()
    avg_bh_ret = res_df["Retorno B&H (1 Año)"].mean()
    avg_dd = res_df["Max Drawdown"].mean()
    avg_trapped = res_df["Días Atrapado"].mean()
    avg_trades = res_df["Trades"].mean()

    return {
        "Arquetipo": label,
        "Casos Evaluados": len(results),
        "Retorno Medio Bot (1 Año)": f"+{avg_bot_ret:,.1f}%",
        "Retorno Medio B&H (1 Año)": f"+{avg_bh_ret:,.1f}%",
        "Drawdown Medio": f"-{avg_dd:.1f}%",
        "Días Atrapado (Medio)": f"{avg_trapped:.0f} días",
        "Trades Medios": f"{avg_trades:.0f}",
        "Detalles": results
    }

def main():
    print("[1/3] Cargando histórico de 9 años de ETH y precalculando condiciones macro...")
    df = load_data()

    print("[2/3] Identificando fechas históricas que cumplen cada arquetipo...")

    # Arquetipo 1: Pozo de Capitulación Extrema (Caída > 60% de ATH y RSI diario en fondo)
    # Suelo histórico 2018 ($85), Caída Covid Marzo 2020 ($110), Colapso Celsius Junio 2022 ($950), FTX Nov 2022 ($1,100)
    capitulation_dates = ["2018-12-15", "2020-03-16", "2022-06-18", "2022-11-21"]

    # Arquetipo 2: Ventana Dorada Macro (Precio cruza sobre EMA 200 diaria con RSI [48, 60] tras consolidación)
    # Enero 2019 ($125), Enero 2020 ($160), Enero 2021 ($750), Octubre 2023 ($1,650)
    golden_window_dates = ["2019-02-18", "2020-01-28", "2020-07-22", "2021-01-03", "2023-10-23"]

    # Arquetipo 3: Zona de Euforia / Techo de Ciclo (Entrada de alto riesgo: >40% sobre EMA 200 diaria + RSI > 70)
    # Enero 2018 ($1,350), Mayo 2021 ($3,800), Noviembre 2021 ($4,600), Marzo 2024 ($3,900)
    euphoria_dates = ["2018-01-13", "2021-05-11", "2021-11-10", "2024-03-12"]

    print("[3/3] Simulando rendimiento de Apex ETH Ultra para cada arquetipo...")
    summary = []

    res_cap = test_archetype(df, capitulation_dates, "1. Pozo de Capitulación (Caída > 60% + RSI Suelo)")
    if res_cap: summary.append(res_cap)

    res_gold = test_archetype(df, golden_window_dates, "2. Ventana Dorada Macro (Cruce y Sostén sobre EMA 200 diaria)")
    if res_gold: summary.append(res_gold)

    res_euph = test_archetype(df, euphoria_dates, "3. Zona de Euforia / Techo (RSI > 70 y >40% sobre EMA 200)")
    if res_euph: summary.append(res_euph)

    # Imprimir tabla comparativa
    table_rows = []
    for s in summary:
        table_rows.append([
            s["Arquetipo"],
            s["Casos Evaluados"],
            s["Retorno Medio Bot (1 Año)"],
            s["Retorno Medio B&H (1 Año)"],
            s["Drawdown Medio"],
            s["Días Atrapado (Medio)"],
            s["Trades Medios"]
        ])

    print("\n" + "=" * 105)
    print("      RADAR DE LANZAMIENTO PARA ETHEREUM: RESULTADOS CUANTITATIVOS A 1 AÑO")
    print("=" * 105)
    print(tabulate(table_rows, headers=["Arquetipo de Entrada", "Muestras", "Retorno Bot (1A)", "Retorno B&H (1A)", "Drawdown Medio", "Días Atrapado", "Trades"], tablefmt="github"))

    # Imprimir desglose de cada caso
    for s in summary:
        print(f"\n--- Detalle: {s['Arquetipo']} ---")
        detail_rows = []
        for d in s["Detalles"]:
            detail_rows.append([
                d["Fecha Entrada"],
                d["Precio ETH"],
                f"+{d['Retorno Bot (1 Año)']:,.1f}%",
                f"+{d['Retorno B&H (1 Año)']:,.1f}%",
                f"-{d['Max Drawdown']:.1f}%",
                f"{d['Días Atrapado']:.0f} d",
                d["Trades"]
            ])
        print(tabulate(detail_rows, headers=["Fecha", "Precio", "Bot 1A", "B&H 1A", "Max DD", "Atrapado", "Trades"], tablefmt="github"))

if __name__ == "__main__":
    main()
