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
from src.strategies.btc_regime import BtcChainedRegimeStrategy
from scripts.experiment_compounding_and_weights import CompoundingChainedStrategy


def run_9year_simulation():
    db = DatabaseManager("data/criptobot.db")
    repo = CandleRepository(db)

    # Cargar los 9 años completos
    df_raw = repo.get_candles_df("BTC/USDT", "1h")
    print(f"Total de velas cargadas en memoria: {len(df_raw)}")
    start_date = df_raw.index[0].strftime("%Y-%m-%d")
    end_date = df_raw.index[-1].strftime("%Y-%m-%d")
    print(f"Rango histórico: {start_date} a {end_date}")

    df = TechnicalIndicators.apply_all(df_raw)

    scenarios = {
        "1. Ciclo Macro 9 Años (Nov 2017 - Sept 2026)": (None, None),
        "2. El Crash Histórico 2018 (BTC $20k a $3.1k, -84%)": (
            int(pd.Timestamp("2017-12-16", tz="UTC").timestamp() * 1000),
            int(pd.Timestamp("2018-12-31", tz="UTC").timestamp() * 1000),
        ),
        "3. Flash Crash Covid 2020 ($10.5k a $3.8k en 30 días)": (
            int(pd.Timestamp("2020-02-15", tz="UTC").timestamp() * 1000),
            int(pd.Timestamp("2020-04-15", tz="UTC").timestamp() * 1000),
        ),
        "4. Gran Desplome 2022 (FTX y Luna, -77%)": (
            int(pd.Timestamp("2021-11-10", tz="UTC").timestamp() * 1000),
            int(pd.Timestamp("2022-12-31", tz="UTC").timestamp() * 1000),
        ),
    }

    engine = SimulationEngine(fee_rate=0.001, enable_profit_recycling=True)

    # Configuraciones:
    # 1. Lineal (Conservador $1,000 fijo)
    cfg_lin = BotConfig(
        bot_id="btc_9y_lin",
        symbol="BTC/USDT",
        budget=1000.0,
        take_profit_pct=5.0,
        max_tranches=5,
        tranche_weights=[0.10, 0.15, 0.20, 0.25, 0.30],
        atr_multiplier=1.5,
        trailing_stop_pct=2.5,
    )
    # 2. Compounding Front-Loaded (Crecimiento Máximo 25/20/20/20/15%)
    cfg_comp = BotConfig(
        bot_id="btc_9y_comp",
        symbol="BTC/USDT",
        budget=1000.0,
        take_profit_pct=5.0,
        max_tranches=5,
        tranche_weights=[0.25, 0.20, 0.20, 0.20, 0.15],
        atr_multiplier=1.5,
        trailing_stop_pct=2.5,
    )

    for sc_name, (start_ts, end_ts) in scenarios.items():
        if start_ts is not None and end_ts is not None:
            sub_df = df[(df["timestamp"] >= start_ts) & (df["timestamp"] <= end_ts)].copy()
        else:
            sub_df = df.copy()

        strat_lin = BtcChainedRegimeStrategy(cfg_lin)
        strat_comp = CompoundingChainedStrategy(cfg_comp, enable_compounding=True)

        m_lin, _, _ = engine.run(strat_lin, sub_df, 1000.0)
        m_comp, _, _ = engine.run(strat_comp, sub_df, 1000.0)

        # Benchmark Buy & Hold
        bh = ((sub_df["close"].iloc[-1] / sub_df["close"].iloc[0]) - 1.0) * 100.0

        results = [
            {
                "Modelo": "1. Lineal ($1k fijo, 10/15/20/25/30%)",
                "Retorno Total": f"{m_lin.total_return_pct:+.2f}%",
                "Capital Final": f"${m_lin.final_equity:.2f}",
                "Max DD": f"-{m_lin.max_drawdown_pct:.2f}%",
                "Flujo Caja Realizado": f"${m_lin.cash_flow_usdt:.2f}",
                "Trades": m_lin.total_trades,
                "Win Rate": f"{m_lin.win_rate_pct:.1f}%",
                "Sharpe": f"{m_lin.sharpe_ratio:.2f}",
            },
            {
                "Modelo": "2. Compounding (Front-Loaded 25/20/20/20/15%)",
                "Retorno Total": f"{m_comp.total_return_pct:+.2f}%",
                "Capital Final": f"${m_comp.final_equity:.2f}",
                "Max DD": f"-{m_comp.max_drawdown_pct:.2f}%",
                "Flujo Caja Realizado": f"${m_comp.cash_flow_usdt:.2f}",
                "Trades": m_comp.total_trades,
                "Win Rate": f"{m_comp.win_rate_pct:.1f}%",
                "Sharpe": f"{m_comp.sharpe_ratio:.2f}",
            },
            {
                "Modelo": "Benchmark: Buy & Hold Bitcoin",
                "Retorno Total": f"{bh:+.2f}%",
                "Capital Final": f"${1000.0 * (1.0 + bh/100.0):.2f}",
                "Max DD": "N/A",
                "Flujo Caja Realizado": "$0.00",
                "Trades": 0,
                "Win Rate": "N/A",
                "Sharpe": "N/A",
            },
        ]

        print(f"\n{'='*110}")
        print(f" RESULTADOS: {sc_name}")
        print(f"{'='*110}")
        print(tabulate(results, headers="keys", tablefmt="github"))


if __name__ == "__main__":
    run_9year_simulation()
