import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import sys
from pathlib import Path
import pandas as pd
from tabulate import tabulate

# Forzar codificación UTF-8 en terminal Windows
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

from src.domain.models import BotConfig
from src.indicators.technical import TechnicalIndicators
from src.simulation.engine import SimulationEngine
from src.storage.candle_repository import CandleRepository
from src.storage.database import DatabaseManager
from src.strategies.btc_macro_compound_regime import BtcMacroCompoundRegimeStrategy
from src.strategies.btc_ultra_compound_regime import BtcUltraCompoundRegimeStrategy
from src.strategies.btc_quantum_compound_regime import BtcQuantumCompoundRegimeStrategy


def run_comparison():
    db = DatabaseManager("data/criptobot.db")
    repo = CandleRepository(db)
    df_raw = repo.get_candles_df("BTC/USDT", "1h")
    df = TechnicalIndicators.apply_all(df_raw)

    initial_capital = 1000.0

    # 1. Configuración Base Macro (25/20, TS 2.5%)
    cfg_macro = BotConfig(
        bot_id="bot_macro",
        symbol="BTC/USDT",
        budget=initial_capital,
        take_profit_pct=5.0,
        max_tranches=5,
        tranche_weights=[0.25, 0.20, 0.20, 0.20, 0.15],
        atr_multiplier=1.5,
        trailing_stop_pct=2.5,
    )

    # 2. Configuración Ultra (Front 30/25, TS 2.0%)
    cfg_ultra = BotConfig(
        bot_id="bot_ultra",
        symbol="BTC/USDT",
        budget=initial_capital,
        take_profit_pct=5.0,
        max_tranches=5,
        tranche_weights=[0.30, 0.25, 0.20, 0.15, 0.10], # 30% en T0 estricto
        atr_multiplier=1.5,
        trailing_stop_pct=2.0,
    )

    # 3. Configuración Quantum (Front 30/25, TS 2.0%, Subsidized Recycling)
    cfg_quantum = BotConfig(
        bot_id="bot_quantum",
        symbol="BTC/USDT",
        budget=initial_capital,
        take_profit_pct=5.0,
        max_tranches=5,
        tranche_weights=[0.30, 0.25, 0.20, 0.15, 0.10], # 30% en T0 estricto
        atr_multiplier=1.5,
        trailing_stop_pct=2.0,
    )

    eng_std = SimulationEngine(fee_rate=0.001, enable_profit_recycling=True, allow_subsidized_discount=False)
    eng_sub = SimulationEngine(
        fee_rate=0.001,
        enable_profit_recycling=True,
        allow_subsidized_discount=True,
        max_subsidized_discount_pct=0.12,
        recycle_profit_fraction=0.35,
        enable_cascading_discount=True,
    )

    scenarios = {
        "full_9y": (None, None, "1. CICLO MACRO COMPLETO 9 AÑOS (Nov 2017 a Sept 2026: 77,514 velas)"),
        "crash_2018": (
            int(pd.Timestamp("2017-12-16", tz="UTC").timestamp() * 1000),
            int(pd.Timestamp("2018-12-31", tz="UTC").timestamp() * 1000),
            "2. EL CRASH HISTÓRICO 2018 (BTC $20k a $3.1k, -84%)",
        ),
        "crash_2022": (
            int(pd.Timestamp("2021-11-10", tz="UTC").timestamp() * 1000),
            int(pd.Timestamp("2022-12-31", tz="UTC").timestamp() * 1000),
            "3. EL GRAN COLAPSO 2022 (FTX y Luna, BTC -77%)",
        ),
        "mega_bull": (
            int(pd.Timestamp("2020-10-01", tz="UTC").timestamp() * 1000),
            int(pd.Timestamp("2021-11-10", tz="UTC").timestamp() * 1000),
            "4. MEGA BULL RUN (2020-2021: BTC $10k a $69k)",
        ),
    }

    for sc_key, (st, et, title) in scenarios.items():
        if st is not None and et is not None:
            sub_df = df[(df["timestamp"] >= st) & (df["timestamp"] <= et)].copy()
        else:
            sub_df = df.copy()

        # Correr las 3 versiones
        strat_macro = BtcMacroCompoundRegimeStrategy(cfg_macro, enable_compounding=True)
        m_macro, _, _ = eng_std.run(strat_macro, sub_df, initial_capital)

        strat_ultra = BtcUltraCompoundRegimeStrategy(cfg_ultra, enable_compounding=True)
        m_ultra, _, _ = eng_std.run(strat_ultra, sub_df, initial_capital)

        strat_quantum = BtcQuantumCompoundRegimeStrategy(cfg_quantum, enable_compounding=True, panic_rsi_threshold=28.0)
        m_quantum, _, _ = eng_sub.run(strat_quantum, sub_df, initial_capital)

        table_data = [
            ["Capital Inicial", f"${initial_capital:.2f}", f"${initial_capital:.2f}", f"${initial_capital:.2f}"],
            ["Equidad Final", f"${m_macro.final_equity:.2f}", f"${m_ultra.final_equity:.2f}", f"${m_quantum.final_equity:.2f}"],
            ["Beneficio Neto", f"${m_macro.net_profit_usdt:.2f}", f"${m_ultra.net_profit_usdt:.2f}", f"${m_quantum.net_profit_usdt:.2f}"],
            ["Retorno Total Bot", f"{m_macro.total_return_pct:+.2f}%", f"{m_ultra.total_return_pct:+.2f}%", f"{m_quantum.total_return_pct:+.2f}%"],
            ["Flujo de Caja Realizado", f"${m_macro.cash_flow_usdt:.2f}", f"${m_ultra.cash_flow_usdt:.2f}", f"${m_quantum.cash_flow_usdt:.2f}"],
            ["Máximo Drawdown", f"-{m_macro.max_drawdown_pct:.2f}%", f"-{m_ultra.max_drawdown_pct:.2f}%", f"-{m_quantum.max_drawdown_pct:.2f}%"],
            ["Trades Cerrados", m_macro.total_trades, m_ultra.total_trades, m_quantum.total_trades],
            ["Win Rate", f"{m_macro.win_rate_pct:.1f}%", f"{m_ultra.win_rate_pct:.1f}%", f"{m_quantum.win_rate_pct:.1f}%"],
            ["Días Máx. Atrapado", f"{m_macro.max_days_trapped:.1f}d", f"{m_ultra.max_days_trapped:.1f}d", f"{m_quantum.max_days_trapped:.1f}d"],
            ["Sharpe Ratio", m_macro.sharpe_ratio, m_ultra.sharpe_ratio, m_quantum.sharpe_ratio],
        ]

        headers = ["Métrica Cuantitativa", "1. Macro (Base 25/20)", "2. Ultra (Front 30/25)", "3. Quantum (Subsidio Dinámico)"]
        print(f"\n{'='*95}")
        print(f" SIMULACIÓN [{title}]")
        print(f"{'='*95}")
        print(tabulate(table_data, headers=headers, tablefmt="github"))


if __name__ == "__main__":
    run_comparison()
