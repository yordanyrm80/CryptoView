import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

import pandas as pd
from tabulate import tabulate

from src.domain.models import BotConfig
from src.indicators.technical import TechnicalIndicators
from src.simulation.engine import SimulationEngine
from src.storage.candle_repository import CandleRepository
from src.storage.database import DatabaseManager
from src.strategies.btc_quantum_evolution_regime import BtcQuantumEvolutionRegimeStrategy


def run_evolution_benchmark():
    db = DatabaseManager()
    repo = CandleRepository(db)
    
    print("[1/3] Loading 9 years of BTC/USDT hourly candles from PostgreSQL database...")
    df_raw = repo.get_candles_df("BTC/USDT", "1h")
    if df_raw.empty:
        print("[!] No candle data found in database. Run fetch_candles script first.")
        return

    print(f"      Loaded {len(df_raw):,} candles (from {pd.to_datetime(df_raw['timestamp'].iloc[0], unit='ms', utc=True)} to {pd.to_datetime(df_raw['timestamp'].iloc[-1], unit='ms', utc=True)}).")

    print("[2/3] Calculating quantitative indicators (EMA 50, EMA 200, Daily EMA 200, ATR 14, RSI 14, ADX 14)...")
    df = TechnicalIndicators.apply_all(df_raw)

    print("[3/3] Executing BtcQuantumEvolutionRegimeStrategy simulation...")
    
    # Official Flagship Configuration
    config = BotConfig(
        bot_id="btc_evolution_flagship",
        symbol="BTC/USDT",
        budget=1000.0,
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

    # Realistic KuCoin Engine (0.1% maker fee, 0.05% stop slippage, 35% cascading profit recycling)
    engine = SimulationEngine(
        fee_rate=0.001,
        stop_slippage=0.0005,
        enable_profit_recycling=True,
        allow_subsidized_discount=True,
        max_subsidized_discount_pct=0.12,
        recycle_profit_fraction=0.35,
        enable_cascading_discount=True,
    )

    initial_capital = 1000.0
    metrics, equity_series, completed_tranches = engine.run(strategy, df, initial_capital=initial_capital)

    # Output Summary Table
    rows = [
        ["Initial Capital", f"${initial_capital:,.2f} USDT"],
        ["Final Equity", f"${metrics.final_equity:,.2f} USDT"],
        ["Total Return", f"{metrics.total_return_pct:+,.2f}%"],
        ["Realized Cash Extracted", f"${metrics.cash_flow_usdt:,.2f} USDT"],
        ["Total Completed Trades", f"{metrics.total_trades}"],
        ["Win Rate", f"{metrics.win_rate_pct:.1f}%"],
        ["Max Floating Drawdown", f"-{metrics.max_drawdown_pct:.2f}%"],
        ["Sharpe Ratio", f"{metrics.sharpe_ratio:.2f}"],
        ["Total Candle History", f"{len(df_raw):,} 1h candles (~9 years)"],
    ]

    print("\n" + "=" * 85)
    print("      OFFICIAL FLAGSHIP BENCHMARK: BTC QUANTUM EVOLUTION REGIME STRATEGY")
    print("=" * 85)
    print(tabulate(rows, headers=["Metric", "Result"], tablefmt="github"))
    print("=" * 85)


if __name__ == "__main__":
    run_evolution_benchmark()
