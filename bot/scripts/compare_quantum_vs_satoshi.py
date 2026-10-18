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
from src.strategies.btc_quantum_satoshi_regime import BtcQuantumSatoshiRegimeStrategy


def run_benchmark():
    db = DatabaseManager("data/criptobot.db")
    repo = CandleRepository(db)
    df_raw = repo.get_candles_df("BTC/USDT", "1h")
    df = TechnicalIndicators.apply_all(df_raw)

    initial_capital = 1000.0

    # Configuración común
    cfg_base = BotConfig(
        bot_id="btc_bench",
        symbol="BTC/USDT",
        budget=initial_capital,
        take_profit_pct=5.0,
        max_tranches=5,
        tranche_weights=[0.30, 0.25, 0.20, 0.15, 0.10],
        atr_multiplier=1.5,
        trailing_stop_pct=2.0,
    )

    # 1. Motor Quantum Original (Descuento contable bajo coste en USDT)
    eng_quantum_orig = SimulationEngine(
        fee_rate=0.001,
        enable_profit_recycling=True,
        allow_subsidized_discount=True,
        max_subsidized_discount_pct=0.12,
        recycle_profit_fraction=0.35,
        enable_cascading_discount=True,
    )

    # 2. Motor Quantum-Satoshi (Subsidio en BTC + Cosecha USDT creciente)
    eng_satoshi_usdt = SimulationEngine(
        fee_rate=0.001,
        enable_profit_recycling=True,
        satoshi_recycling=True,
        recycle_profit_fraction=0.35,
        harvest_mode="USDT",
    )

    # 3. Motor Quantum-Satoshi (Subsidio en BTC + Cosecha SATOSHIS puros libres)
    eng_satoshi_dual = SimulationEngine(
        fee_rate=0.001,
        enable_profit_recycling=True,
        satoshi_recycling=True,
        recycle_profit_fraction=0.35,
        harvest_mode="SATOSHIS",
    )

    scenarios = {
        "full_9y": (None, None, "1. CICLO MACRO COMPLETO 9 AÑOS (Nov 2017 - Sept 2026: 77,514 velas)"),
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

        # V1: Quantum Anterior
        strat_q = BtcQuantumCompoundRegimeStrategy(cfg_base, enable_compounding=True, panic_rsi_threshold=28.0)
        m_q, _, _ = eng_quantum_orig.run(strat_q, sub_df, initial_capital)

        # V2: Quantum-Satoshi (Cosecha USDT)
        strat_s_usdt = BtcQuantumSatoshiRegimeStrategy(cfg_base, enable_compounding=True, panic_rsi_threshold=28.0)
        m_s_usdt, _, _ = eng_satoshi_usdt.run(strat_s_usdt, sub_df, initial_capital)

        # V3: Quantum-Satoshi (Cosecha Satoshis)
        strat_s_dual = BtcQuantumSatoshiRegimeStrategy(cfg_base, enable_compounding=True, panic_rsi_threshold=28.0, harvest_mode="SATOSHIS")
        m_s_dual, _, _ = eng_satoshi_dual.run(strat_s_dual, sub_df, initial_capital)

        table_data = [
            ["Capital Inicial", f"${initial_capital:.2f}", f"${initial_capital:.2f}", f"${initial_capital:.2f}"],
            ["Equidad Final", f"${m_q.final_equity:.2f}", f"${m_s_usdt.final_equity:.2f}", f"${m_s_dual.final_equity:.2f}"],
            ["Beneficio Neto USDT", f"${m_q.net_profit_usdt:.2f}", f"${m_s_usdt.net_profit_usdt:.2f}", f"${m_s_dual.net_profit_usdt:.2f}"],
            ["Retorno Total Bot", f"{m_q.total_return_pct:+.2f}%", f"{m_s_usdt.total_return_pct:+.2f}%", f"{m_s_dual.total_return_pct:+.2f}%"],
            ["Flujo Caja USDT Realizado", f"${m_q.cash_flow_usdt:.2f}", f"${m_s_usdt.cash_flow_usdt:.2f}", f"${m_s_dual.cash_flow_usdt:.2f}"],
            ["Satoshis Subvencionados", "0.00000000 BTC", f"{m_s_usdt.accumulated_satoshis:.8f} BTC", f"{m_s_dual.accumulated_satoshis:.8f} BTC"],
            ["BTC Cosechado Libre (HODL)", "0.00000000 BTC", "0.00000000 BTC", f"{m_s_dual.free_harvested_btc:.8f} BTC"],
            ["Máximo Drawdown", f"-{m_q.max_drawdown_pct:.2f}%", f"-{m_s_usdt.max_drawdown_pct:.2f}%", f"-{m_s_dual.max_drawdown_pct:.2f}%"],
            ["Trades Cerrados", m_q.total_trades, m_s_usdt.total_trades, m_s_dual.total_trades],
            ["Win Rate", f"{m_q.win_rate_pct:.1f}%", f"{m_s_usdt.win_rate_pct:.1f}%", f"{m_s_dual.win_rate_pct:.1f}%"],
            ["Días Máx. Atrapado", f"{m_q.max_days_trapped:.1f}d", f"{m_s_usdt.max_days_trapped:.1f}d", f"{m_s_dual.max_days_trapped:.1f}d"],
            ["Sharpe Ratio", m_q.sharpe_ratio, m_s_usdt.sharpe_ratio, m_s_dual.sharpe_ratio],
        ]

        headers = [
            "Métrica Cuantitativa",
            "1. Quantum Anterior (Apex)",
            "2. Quantum-Satoshi (Cosecha USDT)",
            "3. Quantum-Satoshi (Cosecha BTC)",
        ]
        print(f"\n{'='*110}")
        print(f" SIMULACIÓN [{title}]")
        print(f"{'='*110}")
        print(tabulate(table_data, headers=headers, tablefmt="github"))

    # SIMULACIÓN ESPECIAL: IMPACTO DE LA INYECCIÓN EN EL SUELO DE 2022
    print(f"\n{'='*110}")
    print(f" SIMULACIÓN ESPECIAL: IMPACTO DE INYECCIÓN DE LIQUIDEZ EN EL POZO DE 2022")
    print(f"{'='*110}")
    st_2022 = int(pd.Timestamp("2021-11-10", tz="UTC").timestamp() * 1000)
    et_2022 = int(pd.Timestamp("2022-12-31", tz="UTC").timestamp() * 1000)
    df_crash = df[(df["timestamp"] >= st_2022) & (df["timestamp"] <= et_2022)].copy()

    # Inyección de $1,000 USDT tras la capitulación de Luna (18 de junio de 2022, BTC ~$18k-$20k)
    ts_inyeccion = int(pd.Timestamp("2022-06-18", tz="UTC").timestamp() * 1000)
    inyecciones = [(ts_inyeccion, 1000.0)]

    # A) Sin Inyección
    strat_no_inj = BtcQuantumSatoshiRegimeStrategy(cfg_base, enable_compounding=True)
    m_no_inj, _, _ = eng_satoshi_usdt.run(strat_no_inj, df_crash, initial_capital=1000.0)

    # B) Con Inyección de $1,000 USDT en el fondo
    strat_inj = BtcQuantumSatoshiRegimeStrategy(cfg_base, enable_compounding=True)
    m_inj, _, _ = eng_satoshi_usdt.run(
        strat_inj, df_crash, initial_capital=1000.0, capital_injections=inyecciones
    )

    t_special = [
        ["Capital Inicial Depositado", "$1000.00", "$1000.00"],
        ["Capital Extra Inyectado en Suelo ($18k)", "$0.00", "$1000.00 (Total $2000.00)"],
        ["Equidad Final al Cierre de 2022", f"${m_no_inj.final_equity:.2f}", f"${m_inj.final_equity:.2f}"],
        ["Flujo de Caja Realizado", f"${m_no_inj.cash_flow_usdt:.2f}", f"${m_inj.cash_flow_usdt:.2f}"],
        ["Trades Cerrados en 2022", m_no_inj.total_trades, m_inj.total_trades],
        ["Días Máx. Atrapado en 2022", f"{m_no_inj.max_days_trapped:.1f}d", f"{m_inj.max_days_trapped:.1f}d"],
        ["Satoshis Subvencionados Acumulados", f"{m_no_inj.accumulated_satoshis:.8f} BTC", f"{m_inj.accumulated_satoshis:.8f} BTC"],
    ]
    h_special = ["Métrica en Crash 2022", "Quantum-Satoshi (Sin Inyección)", "Quantum-Satoshi (+ $1,000 en el Fondo)"]
    print(tabulate(t_special, headers=h_special, tablefmt="github"))


if __name__ == "__main__":
    run_benchmark()
