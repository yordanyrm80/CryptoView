import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

from typing import List, Optional
import pandas as pd
from tabulate import tabulate

from src.core.regime_detector import RegimeDetector
from src.domain.models import BotConfig, MarketRegime, TrancheStatus
from src.indicators.technical import TechnicalIndicators
from src.simulation.engine import SimulationEngine
from src.storage.candle_repository import CandleRepository
from src.storage.database import DatabaseManager
from src.strategies.base import ActionSignal, BaseStrategy, PortfolioState, SignalType


class ParametricTrancheStrategy(BaseStrategy):
    """Estrategia paramétrica que permite probar cualquier cantidad de tramos,
    pesos de capital y multiplicadores de ATR encadenados."""

    def __init__(self, config: BotConfig, atr_multipliers: List[float]):
        super().__init__(config)
        self.atr_multipliers = atr_multipliers
        self.trend_highest_price: Optional[float] = None
        self.trend_entry_price: Optional[float] = None

    def evaluate(self, current_row: pd.Series, portfolio: PortfolioState) -> List[ActionSignal]:
        signals: List[ActionSignal] = []
        regime = RegimeDetector.detect_regime(current_row)

        current_price = current_row["close"]
        high_price = current_row["high"]
        low_price = current_row["low"]
        atr_14 = current_row.get("atr_14", current_price * 0.02)
        rsi = current_row.get("rsi_14", 50.0)

        # 1. EVALUACIÓN DE SALIDAS
        for tranche in list(portfolio.active_tranches):
            if tranche.status != TrancheStatus.ACTIVE:
                continue

            # TP Estándar al +5%
            if high_price >= tranche.target_sell_price:
                signals.append(
                    ActionSignal(
                        signal_type=SignalType.SELL_TRANCHE,
                        symbol=self.config.symbol,
                        tranche_index=tranche.tranche_index,
                        price=tranche.target_sell_price,
                        amount=tranche.amount,
                        allocated_usdt=tranche.allocated_budget,
                        reason=f"TP alcanzado",
                        tranche_ref=tranche,
                    )
                )
                continue

            # Trailing Stop en Bull Trend
            if regime == MarketRegime.BULL_TREND and self.trend_highest_price is not None:
                if high_price > self.trend_highest_price:
                    self.trend_highest_price = high_price
                stop_price = self.trend_highest_price * (1.0 - self.config.trailing_stop_pct / 100.0)
                if tranche.buy_price and stop_price > tranche.buy_price and low_price <= stop_price:
                    signals.append(
                        ActionSignal(
                            signal_type=SignalType.SELL_TRANCHE,
                            symbol=self.config.symbol,
                            tranche_index=tranche.tranche_index,
                            price=stop_price,
                            amount=tranche.amount,
                            allocated_usdt=tranche.allocated_budget,
                            reason="Trailing Stop Bull Trend",
                            tranche_ref=tranche,
                        )
                    )
                    self.trend_highest_price = None

        if signals:
            return signals

        # 2. EVALUACIÓN DE ENTRADAS
        occupied = {t.tranche_index: t for t in portfolio.active_tranches if t.status == TrancheStatus.ACTIVE}

        if regime == MarketRegime.RANGE:
            if len(occupied) == 0:
                ema_200 = current_row["ema_200"]
                if current_price >= ema_200 and rsi < 48.0:
                    budget_t0 = self.config.budget * self.config.tranche_weights[0]
                    if portfolio.available_usdt >= budget_t0:
                        signals.append(
                            ActionSignal(
                                signal_type=SignalType.BUY_TRANCHE,
                                symbol=self.config.symbol,
                                tranche_index=0,
                                price=current_price,
                                amount=budget_t0 / current_price,
                                allocated_usdt=budget_t0,
                                target_sell_price=current_price * (1.0 + self.config.take_profit_pct / 100.0),
                                reason="RANGO T0",
                            )
                        )
            else:
                highest_idx = max(occupied.keys())
                next_idx = highest_idx + 1

                if next_idx < self.config.max_tranches and (next_idx - 1) < len(self.atr_multipliers):
                    last_buy_price = occupied[highest_idx].buy_price
                    mult = self.atr_multipliers[next_idx - 1]
                    required_drop = atr_14 * mult
                    target_buy = last_buy_price - required_drop

                    if current_price <= target_buy:
                        budget_t = self.config.budget * self.config.tranche_weights[next_idx]
                        if portfolio.available_usdt >= budget_t:
                            signals.append(
                                ActionSignal(
                                    signal_type=SignalType.BUY_TRANCHE,
                                    symbol=self.config.symbol,
                                    tranche_index=next_idx,
                                    price=current_price,
                                    amount=budget_t / current_price,
                                    allocated_usdt=budget_t,
                                    target_sell_price=current_price * (1.0 + self.config.take_profit_pct / 100.0),
                                    reason=f"RANGO T{next_idx} (-{required_drop:.2f} USDT)",
                                )
                            )

        elif regime == MarketRegime.BULL_TREND:
            if len(occupied) == 0:
                ema_50 = current_row["ema_50"]
                if current_price <= ema_50 * 1.015 or rsi < 55.0:
                    budget_trend = self.config.budget * 0.40
                    if portfolio.available_usdt >= budget_trend:
                        self.trend_highest_price = high_price
                        self.trend_entry_price = current_price
                        signals.append(
                            ActionSignal(
                                signal_type=SignalType.BUY_TRANCHE,
                                symbol=self.config.symbol,
                                tranche_index=0,
                                price=current_price,
                                amount=budget_trend / current_price,
                                allocated_usdt=budget_trend,
                                target_sell_price=current_price * 2.0,
                                reason="TENDENCIA",
                            )
                        )

        elif regime == MarketRegime.PANIC_CAPITULATION:
            if len(occupied) == 0 and rsi < 25.0:
                budget_sniper = self.config.budget * 0.35
                if portfolio.available_usdt >= budget_sniper:
                    signals.append(
                        ActionSignal(
                            signal_type=SignalType.BUY_TRANCHE,
                            symbol=self.config.symbol,
                            tranche_index=0,
                            price=current_price,
                            amount=budget_sniper / current_price,
                            allocated_usdt=budget_sniper,
                            target_sell_price=current_price * 1.05,
                            reason="PÁNICO Sniper",
                        )
                    )

        return signals


def run_experiment():
    db = DatabaseManager("data/criptobot.db")
    repo = CandleRepository(db)
    df_raw = repo.get_candles_df("BTC/USDT", "1h")
    df = TechnicalIndicators.apply_all(df_raw)

    configs_to_test = {
        "3 Tramos (20/35/45%)": {
            "max_tranches": 3,
            "weights": [0.20, 0.35, 0.45],
            "mults": [2.5, 5.5],
        },
        "4 Tramos (15/20/30/35%)": {
            "max_tranches": 4,
            "weights": [0.15, 0.20, 0.30, 0.35],
            "mults": [2.0, 3.8, 6.5],
        },
        "5 Tramos Actual (10/15/20/25/30%)": {
            "max_tranches": 5,
            "weights": [0.10, 0.15, 0.20, 0.25, 0.30],
            "mults": [2.0, 3.5, 5.5, 8.0],
        },
        "5 Tramos Planos (20/20/20/20/20%)": {
            "max_tranches": 5,
            "weights": [0.20, 0.20, 0.20, 0.20, 0.20],
            "mults": [2.0, 3.5, 5.5, 8.0],
        },
        "6 Tramos (8/12/15/18/22/25%)": {
            "max_tranches": 6,
            "weights": [0.08, 0.12, 0.15, 0.18, 0.22, 0.25],
            "mults": [1.8, 3.0, 4.5, 6.5, 9.5],
        },
        "7 Tramos (5/8/12/15/18/20/22%)": {
            "max_tranches": 7,
            "weights": [0.05, 0.08, 0.12, 0.15, 0.18, 0.20, 0.22],
            "mults": [1.5, 2.5, 4.0, 6.0, 8.5, 12.0],
        },
    }

    scenarios = {
        "1. Ciclo Completo 6 Años (2020-2026)": (None, None),
        "2. Crash 2022 (-77% Caída)": (
            int(pd.Timestamp("2021-11-10", tz="UTC").timestamp() * 1000),
            int(pd.Timestamp("2022-12-31", tz="UTC").timestamp() * 1000),
        ),
        "3. Mega Bull Run (2020-2021)": (
            int(pd.Timestamp("2020-10-01", tz="UTC").timestamp() * 1000),
            int(pd.Timestamp("2021-11-10", tz="UTC").timestamp() * 1000),
        ),
    }

    engine = SimulationEngine(fee_rate=0.001, enable_profit_recycling=True)

    for sc_name, (start_ts, end_ts) in scenarios.items():
        if start_ts is not None and end_ts is not None:
            sub_df = df[(df["timestamp"] >= start_ts) & (df["timestamp"] <= end_ts)].copy()
        else:
            sub_df = df.copy()

        results = []
        for name, spec in configs_to_test.items():
            cfg = BotConfig(
                bot_id=f"cfg_{spec['max_tranches']}",
                symbol="BTC/USDT",
                budget=1000.0,
                take_profit_pct=5.0,
                max_tranches=spec["max_tranches"],
                tranche_weights=spec["weights"],
                atr_multiplier=1.5,
                trailing_stop_pct=2.5,
            )
            strat = ParametricTrancheStrategy(cfg, spec["mults"])
            m, _, _ = engine.run(strat, sub_df, 1000.0)
            results.append({
                "Configuración de Tramos": name,
                "Retorno Total": f"{m.total_return_pct:+.2f}%",
                "Max DD": f"-{m.max_drawdown_pct:.2f}%",
                "Flujo Caja": f"${m.cash_flow_usdt:.2f}",
                "Trades": m.total_trades,
                "Win Rate": f"{m.win_rate_pct:.1f}%",
                "Días Atrapado": f"{m.max_days_trapped:.1f}d",
                "Sharpe": f"{m.sharpe_ratio:.2f}",
            })

        print(f"\n{'='*105}")
        print(f" EXPERIMENTO DE NÚMERO Y DISTRIBUCIÓN DE TRAMOS: {sc_name}")
        print(f"{'='*105}")
        print(tabulate(results, headers="keys", tablefmt="github"))


if __name__ == "__main__":
    run_experiment()
