import sys
import os
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

import psycopg2
import pandas as pd
import numpy as np

from src.indicators.technical import TechnicalIndicators
from src.domain.models import BotConfig, TrancheStatus
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

    df_full = TechnicalIndicators.apply_all(df_raw)
    start_filter = pd.Timestamp("2021-11-07 00:00:00", tz="UTC")
    df = df_full[df_full.index >= start_filter].copy()
    return df

def create_bot(bot_id: str, budget: float):
    config = BotConfig(
        bot_id=bot_id,
        symbol="BTC/USDT",
        budget=budget,
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
    return strategy

def create_engine():
    return SimulationEngine(
        fee_rate=0.001,
        stop_slippage=0.0005,
        enable_profit_recycling=True,
        allow_subsidized_discount=True,
        max_subsidized_discount_pct=0.12,
        recycle_profit_fraction=0.35,
        enable_cascading_discount=True,
    )

def run():
    df = load_candles()
    start_price = df.iloc[0]['open']
    end_price = df.iloc[-1]['close']
    print(f"Velas cargadas: {len(df)} (Desde {df.index[0]} @ ${start_price:,.2f} hasta {df.index[-1]} @ ${end_price:,.2f})")
    
    # 1. Correr el bot normal (BtcQuantumEvolutionRegime original que rescata y vende tramos)
    engine_orig = create_engine()
    strat_orig = create_bot("bot_orig", 2000.0)
    metrics_orig, eq_orig, comp_orig = engine_orig.run(strat_orig, df, initial_capital=2000.0)
    
    print("\n" + "=" * 65)
    print("1. RESULTADO BOT ORIGINAL (Rescatando y vendiendo tramos con cascada)")
    print("=" * 65)
    print(f"Equidad Final:   ${metrics_orig.final_equity:,.2f} USDT")
    print(f"Retorno:         +{metrics_orig.total_return_pct:.2f}%")
    print(f"Cash extraído:   ${metrics_orig.cash_flow_usdt:,.2f} USDT")
    print(f"Trades cerrados: {metrics_orig.total_trades} (Win Rate: {metrics_orig.win_rate_pct:.1f}%)")
    
    # 2. Encontrar el fondo absoluto del mercado (Nov 2022 / $15,483)
    min_idx_pos = df['low'].values.argmin()
    min_time = df.index[min_idx_pos]
    min_price = df['low'].iloc[min_idx_pos]
    print(f"\nSuelo del mercado en el periodo: {min_time} @ ${min_price:,.2f}")
    
    # Ejecutar hasta el suelo para ver exactamente qué tramos y saldos tiene
    df_to_bottom = df.iloc[:min_idx_pos+1].copy()
    strat_step = create_bot("bot_step", 2000.0)
    engine_step = create_engine()
    metrics_bottom, eq_bottom, comp_bottom = engine_step.run(strat_step, df_to_bottom, initial_capital=2000.0)
    
    portfolio_bottom = engine_step.last_portfolio
    active_tranches = portfolio_bottom.active_tranches
    total_btc_trapped = sum(t.amount for t in active_tranches)
    total_cost_usdt = sum(t.allocated_budget for t in active_tranches)
    avg_buy_price = total_cost_usdt / total_btc_trapped if total_btc_trapped > 0 else 0
    
    cash_at_bottom = portfolio_bottom.available_usdt
    cash_extracted_so_far = metrics_bottom.cash_flow_usdt
    
    print("\n" + "-" * 65)
    print("ESTADO DEL BOT EN EL FONDO (Noviembre 2022)")
    print("-" * 65)
    print(f"Tramos activos atrapados: {len(active_tranches)}")
    for t in active_tranches:
        print(f"  - Tramo {t.tranche_index}: {t.amount:.6f} BTC comprado @ ${t.buy_price:,.2f} (Costo: ${t.allocated_budget:,.2f} USDT)")
    print(f"\nTotal BTC en tramos atrapados: {total_btc_trapped:.6f} BTC")
    print(f"Costo invertido en ese BTC:    ${total_cost_usdt:,.2f} USDT")
    print(f"Precio promedio de compra:     ${avg_buy_price:,.2f}")
    print(f"USDT líquido libre en cartera: ${cash_at_bottom:,.2f} USDT")
    print(f"Cash extraído antes del suelo: ${cash_extracted_so_far:,.2f} USDT")
    
    # Valor de ese BTC si se congela en HOLD puro hasta Nov 2026 ($75,822)
    val_btc_at_end = total_btc_trapped * end_price
    print(f"\nSi este BTC ({total_btc_trapped:.6f} BTC) se deja en HOLD hasta Nov 2026:")
    print(f"-> Valor a ${end_price:,.2f}: ${val_btc_at_end:,.2f} USDT (Ganancia neta: +${val_btc_at_end - total_cost_usdt:,.2f})")
    
    # 3. Simular el Bot Limpio con el USDT residual desde el suelo
    df_from_bottom = df.iloc[min_idx_pos:].copy()
    
    print(f"\nUSDT residual disponible para el Bot Gemelo: ${cash_at_bottom:,.2f}")
    if cash_at_bottom >= 10.0:
        strat_residual = create_bot("bot_residual", cash_at_bottom)
        # Desactivamos reciclaje a tramos viejos porque ya no tiene tramos viejos que rescatar
        engine_residual = create_engine()
        metrics_res, eq_res, comp_res = engine_residual.run(strat_residual, df_from_bottom, initial_capital=cash_at_bottom)
        residual_end_eq = metrics_res.final_equity
        residual_cash = metrics_res.cash_flow_usdt
        trades_residual = metrics_res.total_trades
        wr_residual = metrics_res.win_rate_pct
    else:
        residual_end_eq = cash_at_bottom
        residual_cash = 0.0
        trades_residual = 0
        wr_residual = 0.0
        
    print("\n" + "-" * 65)
    print(f"RENDIMIENTO DEL BOT RESIDUAL (${cash_at_bottom:,.2f} USDT iniciales)")
    print("-" * 65)
    print(f"Equidad Final del Bot Residual: ${residual_end_eq:,.2f} USDT")
    print(f"Cash extraído por el Bot:       ${residual_cash:,.2f} USDT")
    print(f"Trades cerrados:                {trades_residual} (Win Rate: {wr_residual:.1f}%)")
    
    # Balance total del portafolio:
    # 1. El BTC congelado en HOLD
    # 2. La equidad final generada por el bot residual
    # 3. Todo el efectivo ya extraído a lo largo de los 5 años
    total_strat_equity = val_btc_at_end + residual_end_eq + cash_extracted_so_far + residual_cash
    
    print("\n" + "=" * 65)
    print("BALANCE FINAL: CONGELAR BTC EN HOLD + BOT LIMPIO RESIDUAL")
    print("=" * 65)
    print(f"1. BTC en HOLD ({total_btc_trapped:.6f} BTC @ ${end_price:,.2f}):  ${val_btc_at_end:,.2f} USDT")
    print(f"2. Equidad Final Bot Residual:                ${residual_end_eq:,.2f} USDT")
    print(f"3. Cash Total Extraído en Mano:               ${cash_extracted_so_far + residual_cash:,.2f} USDT")
    print("-" * 65)
    print(f"PATRIMONIO TOTAL COMBINADO:                   ${total_strat_equity:,.2f} USDT")
    print(f"Retorno Neto sobre los $2,000 iniciales:      +{((total_strat_equity - 2000.0) / 2000.0)*100:.2f}%")
    print(f"Diferencia vs Bot Original que rescata:       ${total_strat_equity - metrics_orig.final_equity:+,.2f} USDT")
    print("=" * 65)

if __name__ == "__main__":
    run()
