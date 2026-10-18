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
from src.strategies.btc_quantum_compound_regime import BtcQuantumCompoundRegimeStrategy
from src.strategies.btc_quantum_reload_regime import BtcQuantumReloadRegimeStrategy


def run_reload_simulation():
    db = DatabaseManager("data/criptobot.db")
    repo = CandleRepository(db)
    df_raw = repo.get_candles_df("BTC/USDT", "1h")
    df = TechnicalIndicators.apply_all(df_raw)

    initial_capital = 1000.0

    cfg_base = BotConfig(
        bot_id="btc_apex",
        symbol="BTC/USDT",
        budget=initial_capital,
        take_profit_pct=5.0,
        max_tranches=5,
        tranche_weights=[0.30, 0.25, 0.20, 0.15, 0.10],
        atr_multiplier=1.5,
        trailing_stop_pct=2.0,
    )

    # Motor de Subsidio en Cascada Líquido (El que dio +1,995%)
    eng = SimulationEngine(
        fee_rate=0.001,
        enable_profit_recycling=True,
        allow_subsidized_discount=True,
        max_subsidized_discount_pct=0.12,
        recycle_profit_fraction=0.35,
        enable_cascading_discount=True,
        satoshi_recycling=False,
    )

    # Timestamps de inyecciones clave
    ts_suelo_2018 = int(pd.Timestamp("2018-12-15", tz="UTC").timestamp() * 1000)  # BTC ~$3,200
    ts_suelo_2022 = int(pd.Timestamp("2022-06-18", tz="UTC").timestamp() * 1000)  # BTC ~$18,000

    scenarios = {
        "crash_2022": (
            int(pd.Timestamp("2021-11-10", tz="UTC").timestamp() * 1000),
            int(pd.Timestamp("2022-12-31", tz="UTC").timestamp() * 1000),
            "1. IMPACTO DIRECTO EN EL COLAPSO 2022 (FTX y Luna, BTC -77%)",
            [(ts_suelo_2022, 1000.0)],
            [],  # Dual en 2022 es solo 2022
        ),
        "full_9y": (
            None,
            None,
            "2. CICLO MACRO COMPLETO 9 AÑOS (Noviembre 2017 - Septiembre 2026: 77,514 velas)",
            [(ts_suelo_2022, 1000.0)],
            [(ts_suelo_2018, 500.0), (ts_suelo_2022, 1000.0)],
        ),
    }

    for sc_key, (st, et, title, inj_2022, inj_dual) in scenarios.items():
        if st is not None and et is not None:
            sub_df = df[(df["timestamp"] >= st) & (df["timestamp"] <= et)].copy()
        else:
            sub_df = df.copy()

        # CASO 1: BASE APEX (Sin inyección externa)
        strat_base = BtcQuantumCompoundRegimeStrategy(cfg_base, enable_compounding=True)
        m_base, _, _ = eng.run(strat_base, sub_df, initial_capital=initial_capital)

        # CASO 2: APEX + INYECCIÓN 2022 ($1,000 en el pozo de $18k con Tramos de Suelo)
        strat_r22 = BtcQuantumReloadRegimeStrategy(cfg_base, enable_compounding=True)
        m_r22, _, _ = eng.run(
            strat_r22, sub_df, initial_capital=initial_capital, capital_injections=inj_2022
        )

        # CASO 3: APEX + INYECCIÓN DUAL (2018 +$500 y 2022 +$1,000 con Tramos de Suelo)
        strat_r_dual = BtcQuantumReloadRegimeStrategy(cfg_base, enable_compounding=True)
        m_r_dual, _, _ = eng.run(
            strat_r_dual, sub_df, initial_capital=initial_capital, capital_injections=inj_dual
        )

        cap_dep_base = m_base.capital_inicial
        cap_dep_r22 = m_r22.capital_inicial
        cap_dep_dual = m_r_dual.capital_inicial

        table_data = [
            ["Capital Total Depositado", f"${cap_dep_base:.2f}", f"${cap_dep_r22:.2f}", f"${cap_dep_dual:.2f}"],
            ["Equidad Final", f"${m_base.final_equity:.2f}", f"${m_r22.final_equity:.2f}", f"${m_r_dual.final_equity:.2f}"],
            ["Beneficio Neto Real (Ganancia)", f"${m_base.net_profit_usdt:.2f}", f"${m_r22.net_profit_usdt:.2f}", f"${m_r_dual.net_profit_usdt:.2f}"],
            ["Retorno Total Sobre Capital Invertido", f"{m_base.total_return_pct:+.2f}%", f"{m_r22.total_return_pct:+.2f}%", f"{m_r_dual.total_return_pct:+.2f}%"],
            ["Flujo de Caja Extraído en Efectivo", f"${m_base.cash_flow_usdt:.2f}", f"${m_r22.cash_flow_usdt:.2f}", f"${m_r_dual.cash_flow_usdt:.2f}"],
            ["Trades Cerrados", m_base.total_trades, m_r22.total_trades, m_r_dual.total_trades],
            ["Win Rate", f"{m_base.win_rate_pct:.1f}%", f"{m_r22.win_rate_pct:.1f}%", f"{m_r_dual.win_rate_pct:.1f}%"],
            ["Días Máximo Atrapado", f"{m_base.max_days_trapped:.1f}d", f"{m_r22.max_days_trapped:.1f}d", f"{m_r_dual.max_days_trapped:.1f}d"],
            ["Máximo Drawdown", f"-{m_base.max_drawdown_pct:.2f}%", f"-{m_r22.max_drawdown_pct:.2f}%", f"-{m_r_dual.max_drawdown_pct:.2f}%"],
            ["Sharpe Ratio", m_base.sharpe_ratio, m_r22.sharpe_ratio, m_r_dual.sharpe_ratio],
        ]

        headers = [
            "Métrica Cuantitativa",
            "1. Apex Base (Sin Inyección)",
            "2. Apex + Suelo 2022 (+$1k)",
            "3. Apex + Dual (2018 +$500, 2022 +$1k)",
        ]

        print(f"\n{'='*115}")
        print(f" SIMULACIÓN DE INYECCIÓN DE SUELO: [{title}]")
        print(f"{'='*115}")
        print(tabulate(table_data, headers=headers, tablefmt="github"))


if __name__ == "__main__":
    run_reload_simulation()
