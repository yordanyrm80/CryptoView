import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import argparse
import sys
from pathlib import Path
from typing import Optional, List
import pandas as pd

# Forzar UTF-8 en stdout para evitar errores de codificación en Windows
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

from tabulate import tabulate

from src.domain.models import BotConfig
from src.indicators.technical import TechnicalIndicators
from src.simulation.engine import SimulationEngine
from src.storage.candle_repository import CandleRepository
from src.storage.database import DatabaseManager
from src.strategies.btc_compound_regime import BtcCompoundRegimeStrategy
from src.strategies.btc_macro_compound_regime import BtcMacroCompoundRegimeStrategy
from src.strategies.btc_quantum_evolution_regime import BtcQuantumEvolutionRegimeStrategy
from src.strategies.btc_regime import BtcChainedRegimeStrategy
from src.strategies.naive_grid import NaiveGridStrategy
from src.strategies.three_regime import AdaptiveThreeRegimeStrategy
from src.strategies.trend_following import TrendFollowingStrategy


def run_comparison_for_symbol(
    repo: CandleRepository,
    symbol: str,
    timeframe: str,
    initial_capital: float = 1000.0,
    take_profit_pct: float = 5.0,
    fee_rate: float = 0.001,
    start_time: Optional[int] = None,
    end_time: Optional[int] = None,
    scenario_label: str = "Ciclo Completo",
):
    df_raw = repo.get_candles_df(symbol, timeframe, start_time=start_time, end_time=end_time)
    if df_raw.empty:
        print(f"[!] No hay datos para {symbol} en {timeframe} en el rango seleccionado.")
        return None

    # Precalcular indicadores cuantitativos
    df_with_indicators = TechnicalIndicators.apply_all(df_raw)

    # Configuración de Bot
    config = BotConfig(
        bot_id=f"bot_{symbol.replace('/', '_').lower()}",
        symbol=symbol,
        budget=initial_capital,
        take_profit_pct=take_profit_pct,
        max_tranches=5,
        tranche_weights=[0.10, 0.15, 0.20, 0.25, 0.30],
        atr_multiplier=1.5,
        trailing_stop_pct=2.5,
    )

    engine_rec = SimulationEngine(fee_rate=fee_rate, enable_profit_recycling=True)
    engine_norec = SimulationEngine(fee_rate=fee_rate, enable_profit_recycling=False)

    # 1. Grid Naive
    naive_strat = NaiveGridStrategy(config)
    m_naive, _, _ = engine_norec.run(naive_strat, df_with_indicators, initial_capital)

    m_col4 = None
    col4_header = None

    if "BTC" in symbol:
        # Para BTC comparamos:
        # Col 2: BTC Compound Base (Filtro 1h EMA 200)
        # Col 3: BTC Macro Compound (Filtro Macro Daily EMA 200 Multi-Temporalidad)
        # Col 4: BTC Quantum Evolution Flagship (Trend 70%, TS 1.4%, Auto Floor, Cascading Recycling)
        config_compound = BotConfig(
            bot_id=f"bot_{symbol.replace('/', '_').lower()}_compound",
            symbol=symbol,
            budget=initial_capital,
            take_profit_pct=take_profit_pct,
            max_tranches=5,
            tranche_weights=[0.25, 0.20, 0.20, 0.20, 0.15],
            atr_multiplier=1.5,
            trailing_stop_pct=2.5,
        )
        strat_btc_base = BtcCompoundRegimeStrategy(config_compound, enable_compounding=True)
        m_col2, _, _ = engine_rec.run(strat_btc_base, df_with_indicators, initial_capital)

        strat_btc_macro = BtcMacroCompoundRegimeStrategy(
            config_compound, enable_compounding=True, macro_indicator="ema_daily_200"
        )
        m_col3, _, _ = engine_rec.run(strat_btc_macro, df_with_indicators, initial_capital)

        config_evo = BotConfig(
            bot_id=f"bot_{symbol.replace('/', '_').lower()}_evolution",
            symbol=symbol,
            budget=initial_capital,
            take_profit_pct=4.5,
            max_tranches=8,
            tranche_weights=[0.30, 0.25, 0.20, 0.15, 0.10, 0.40, 0.35, 0.25],
            atr_multiplier=1.5,
            trailing_stop_pct=1.4,
        )
        strat_btc_evo = BtcQuantumEvolutionRegimeStrategy(
            config_evo,
            enable_compounding=True,
            trend_weight=0.70,
            trailing_stop_pct=1.4,
        )
        m_col4, _, _ = engine_rec.run(strat_btc_evo, df_with_indicators, initial_capital)

        col2_header = "BTC Compound (1h)"
        col3_header = "BTC Macro (Daily)"
        col4_header = "Quantum Evolution (Apex Flagship)"
    else:
        # Para ETH/LTC:
        strat_norec = AdaptiveThreeRegimeStrategy(config)
        m_col2, _, _ = engine_norec.run(strat_norec, df_with_indicators, initial_capital)

        strat_rec = AdaptiveThreeRegimeStrategy(config)
        m_col3, _, _ = engine_rec.run(strat_rec, df_with_indicators, initial_capital)
        col2_header = "3 Regímenes (SIN Reciclaje)"
        col3_header = "3 Regímenes (CON Reciclaje)"

    # Rango de fechas evaluado
    start_date = df_raw.index[0].strftime("%Y-%m-%d")
    end_date = df_raw.index[-1].strftime("%Y-%m-%d")
    total_candles = len(df_raw)

    if m_col4 is not None:
        table_headers = ["Métrica Cuantitativa", "Grid Naive", col2_header, col3_header, col4_header]
        table_data = [
            ["Escenario / Fechas", f"{scenario_label}: {start_date} a {end_date} ({total_candles} velas)", "", "", ""],
            ["Capital Inicial", f"${initial_capital:.2f}", f"${initial_capital:.2f}", f"${initial_capital:.2f}", f"${initial_capital:.2f}"],
            ["Capital Final (Equidad)", f"${m_naive.final_equity:.2f}", f"${m_col2.final_equity:.2f}", f"${m_col3.final_equity:.2f}", f"${m_col4.final_equity:.2f}"],
            ["Beneficio Neto", f"${m_naive.net_profit_usdt:.2f}", f"${m_col2.net_profit_usdt:.2f}", f"${m_col3.net_profit_usdt:.2f}", f"${m_col4.net_profit_usdt:.2f}"],
            ["Retorno Total Bot", f"{m_naive.total_return_pct:+.2f}%", f"{m_col2.total_return_pct:+.2f}%", f"{m_col3.total_return_pct:+.2f}%", f"{m_col4.total_return_pct:+.2f}%"],
            ["Benchmark Buy & Hold", f"{m_naive.buy_and_hold_return_pct:+.2f}%", f"{m_col2.buy_and_hold_return_pct:+.2f}%", f"{m_col3.buy_and_hold_return_pct:+.2f}%", f"{m_col4.buy_and_hold_return_pct:+.2f}%"],
            ["Máximo Drawdown", f"-{m_naive.max_drawdown_pct:.2f}%", f"-{m_col2.max_drawdown_pct:.2f}%", f"-{m_col3.max_drawdown_pct:.2f}%", f"-{m_col4.max_drawdown_pct:.2f}%"],
            ["Total Trades", m_naive.total_trades, m_col2.total_trades, m_col3.total_trades, m_col4.total_trades],
            ["Win Rate", f"{m_naive.win_rate_pct:.1f}%", f"{m_col2.win_rate_pct:.1f}%", f"{m_col3.win_rate_pct:.1f}%", f"{m_col4.win_rate_pct:.1f}%"],
            ["Profit Factor", m_naive.profit_factor, m_col2.profit_factor, m_col3.profit_factor, m_col4.profit_factor],
            ["Flujo de Caja Realizado", f"${m_naive.cash_flow_usdt:.2f}", f"${m_col2.cash_flow_usdt:.2f}", f"${m_col3.cash_flow_usdt:.2f}", f"${m_col4.cash_flow_usdt:.2f}"],
            ["Días Máx. Atrapado", f"{m_naive.max_days_trapped:.1f}d", f"{m_col2.max_days_trapped:.1f}d", f"{m_col3.max_days_trapped:.1f}d", f"{m_col4.max_days_trapped:.1f}d"],
            ["Comisiones KuCoin", f"${m_naive.total_fees_paid:.2f}", f"${m_col2.total_fees_paid:.2f}", f"${m_col3.total_fees_paid:.2f}", f"${m_col4.total_fees_paid:.2f}"],
            ["Sharpe Ratio", m_naive.sharpe_ratio, m_col2.sharpe_ratio, m_col3.sharpe_ratio, m_col4.sharpe_ratio],
        ]
    else:
        table_headers = ["Métrica Cuantitativa", "Grid Naive", col2_header, col3_header]
        table_data = [
            ["Escenario / Fechas", f"{scenario_label}: {start_date} a {end_date} ({total_candles} velas)", "", ""],
            ["Capital Inicial", f"${initial_capital:.2f} USDT", f"${initial_capital:.2f} USDT", f"${initial_capital:.2f} USDT"],
            ["Capital Final (Equidad)", f"${m_naive.final_equity:.2f} USDT", f"${m_col2.final_equity:.2f} USDT", f"${m_col3.final_equity:.2f} USDT"],
            ["Beneficio Neto", f"${m_naive.net_profit_usdt:.2f} USDT", f"${m_col2.net_profit_usdt:.2f} USDT", f"${m_col3.net_profit_usdt:.2f} USDT"],
            ["Retorno Total Bot", f"{m_naive.total_return_pct:+.2f}%", f"{m_col2.total_return_pct:+.2f}%", f"{m_col3.total_return_pct:+.2f}%"],
            ["Benchmark Buy & Hold", f"{m_naive.buy_and_hold_return_pct:+.2f}%", f"{m_col2.buy_and_hold_return_pct:+.2f}%", f"{m_col3.buy_and_hold_return_pct:+.2f}%"],
            ["Máximo Drawdown (Caída pico)", f"-{m_naive.max_drawdown_pct:.2f}%", f"-{m_col2.max_drawdown_pct:.2f}%", f"-{m_col3.max_drawdown_pct:.2f}%"],
            ["Total Operaciones Cerradas", m_naive.total_trades, m_col2.total_trades, m_col3.total_trades],
            ["Tasa de Acierto (Win Rate)", f"{m_naive.win_rate_pct:.1f}%", f"{m_col2.win_rate_pct:.1f}%", f"{m_col3.win_rate_pct:.1f}%"],
            ["Profit Factor", m_naive.profit_factor, m_col2.profit_factor, m_col3.profit_factor],
            ["Flujo de Caja Realizado", f"${m_naive.cash_flow_usdt:.2f} USDT", f"${m_col2.cash_flow_usdt:.2f} USDT", f"${m_col3.cash_flow_usdt:.2f} USDT"],
            ["Días Máx. Capital Atrapado", f"{m_naive.max_days_trapped:.1f} días", f"{m_col2.max_days_trapped:.1f} días", f"{m_col3.max_days_trapped:.1f} días"],
            ["Comisiones Pagadas a KuCoin", f"${m_naive.total_fees_paid:.2f} USDT", f"${m_col2.total_fees_paid:.2f} USDT", f"${m_col3.total_fees_paid:.2f} USDT"],
            ["Sharpe Ratio (Anualizado)", m_naive.sharpe_ratio, m_col2.sharpe_ratio, m_col3.sharpe_ratio],
        ]

    print(f"\n{'='*110}")
    print(f" SIMULACIÓN [{scenario_label}]: {symbol} ({start_date} a {end_date})")
    print(f"{'='*110}")
    print(tabulate(table_data, headers=table_headers, tablefmt="github"))
    return m_naive, m_col2, m_col3


def main():
    parser = argparse.ArgumentParser(description="Simulación Multiescenario de Estrategias Cuantitativas")
    parser.add_argument("--db", default=None, help="URL de base de datos PostgreSQL")
    parser.add_argument("--timeframe", default="1h", help="Temporalidad a evaluar")
    parser.add_argument("--capital", type=float, default=1000.0, help="Capital inicial en USDT por bot")
    parser.add_argument("--symbol", default="BTC/USDT", help="Símbolo a evaluar (por defecto BTC/USDT)")
    parser.add_argument("--scenario", choices=["all", "crash_2018", "covid_2020", "mega_bull", "crash_2022", "bear_recent", "full"], default="all")
    args = parser.parse_args()

    db_manager = DatabaseManager(args.db)
    repo = CandleRepository(db_manager)

    symbol = args.symbol
    tp = 5.0 if "BTC" in symbol else 10.0

    # Definición de ventanas temporales sobre los casi 9 años reales de datos (2017 a 2026)
    scenarios = {
        "crash_2018": {
            "label": "1. EL CRASH HISTÓRICO 2018 (BTC $20k a $3.1k, -84%)",
            "start": int(pd.Timestamp("2017-12-16", tz="UTC").timestamp() * 1000),
            "end": int(pd.Timestamp("2018-12-31", tz="UTC").timestamp() * 1000),
        },
        "covid_2020": {
            "label": "2. FLASH CRASH COVID (Marzo 2020, $10.5k a $3.8k en 30 días)",
            "start": int(pd.Timestamp("2020-02-15", tz="UTC").timestamp() * 1000),
            "end": int(pd.Timestamp("2020-04-15", tz="UTC").timestamp() * 1000),
        },
        "mega_bull": {
            "label": "3. MEGA BULL RUN (2020-2021: BTC $10k a $69k)",
            "start": int(pd.Timestamp("2020-10-01", tz="UTC").timestamp() * 1000),
            "end": int(pd.Timestamp("2021-11-10", tz="UTC").timestamp() * 1000),
        },
        "crash_2022": {
            "label": "4. EL GRAN COLAPSO (Crash 2022: Luna y FTX, BTC -77%)",
            "start": int(pd.Timestamp("2021-11-10", tz="UTC").timestamp() * 1000),
            "end": int(pd.Timestamp("2022-12-31", tz="UTC").timestamp() * 1000),
        },
        "bear_recent": {
            "label": "5. MERCADO BAJISTA RECIENTE (Sept 2025 a Sept 2026)",
            "start": int(pd.Timestamp("2025-09-01", tz="UTC").timestamp() * 1000),
            "end": int(pd.Timestamp("2026-09-01", tz="UTC").timestamp() * 1000),
        },
        "full": {
            "label": "6. CICLO MACRO COMPLETO 9 AÑOS (Nov 2017 a Sept 2026: 77,514 velas)",
            "start": None,
            "end": None,
        },
    }

    selected = [args.scenario] if args.scenario != "all" else ["crash_2018", "covid_2020", "mega_bull", "crash_2022", "bear_recent", "full"]

    for sc_key in selected:
        sc = scenarios[sc_key]
        run_comparison_for_symbol(
            repo=repo,
            symbol=symbol,
            timeframe=args.timeframe,
            initial_capital=args.capital,
            take_profit_pct=tp,
            start_time=sc["start"],
            end_time=sc["end"],
            scenario_label=sc["label"],
        )


if __name__ == "__main__":
    main()
