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


class CompoundingChainedStrategy(BaseStrategy):
    """Estrategia de ATR Encadenado con capacidad de Interés Compuesto Dinámico:
    Si enable_compounding es True, el tamaño de cada tramo se calcula sobre el capital
    total de la cuenta (Equidad o Saldo Realizado), no sobre el budget inicial fijo.
    """

    def __init__(self, config: BotConfig, enable_compounding: bool = True):
        super().__init__(config)
        self.enable_compounding = enable_compounding
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

        # Salidas
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
                            reason="Trailing Stop",
                            tranche_ref=tranche,
                        )
                    )
                    self.trend_highest_price = None

        if signals:
            return signals

        # Base de capital para calcular el tramo
        if self.enable_compounding:
            # Base compuesta = capital inicial + ganancias realizadas netas
            effective_base = self.config.budget + max(0.0, portfolio.total_realized_profit)
        else:
            effective_base = self.config.budget

        occupied = {t.tranche_index: t for t in portfolio.active_tranches if t.status == TrancheStatus.ACTIVE}

        if regime == MarketRegime.RANGE:
            if len(occupied) == 0:
                ema_200 = current_row["ema_200"]
                if current_price >= ema_200 and rsi < 48.0:
                    budget_t0 = effective_base * self.config.tranche_weights[0]
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

                if next_idx < self.config.max_tranches:
                    last_buy_price = occupied[highest_idx].buy_price
                    atr_mults = [2.0, 3.5, 5.5, 8.0]
                    mult = atr_mults[min(next_idx - 1, len(atr_mults) - 1)]
                    required_drop = atr_14 * mult
                    target_buy = last_buy_price - required_drop

                    if current_price <= target_buy:
                        budget_t = effective_base * self.config.tranche_weights[next_idx]
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
                                    reason=f"RANGO T{next_idx}",
                                )
                            )

        elif regime == MarketRegime.BULL_TREND:
            if len(occupied) == 0:
                ema_50 = current_row["ema_50"]
                if current_price <= ema_50 * 1.015 or rsi < 55.0:
                    budget_trend = effective_base * 0.40
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
                budget_sniper = effective_base * 0.35
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

    configs = {
        "1. Actual (Sin Compounding, Pesos 10/15/20/25/30%)": {
            "compounding": False,
            "weights": [0.10, 0.15, 0.20, 0.25, 0.30],
        },
        "2. Con Compounding Dinámico (Pesos 10/15/20/25/30%)": {
            "compounding": True,
            "weights": [0.10, 0.15, 0.20, 0.25, 0.30],
        },
        "3. Con Compounding + Pesos Planos (20/20/20/20/20%)": {
            "compounding": True,
            "weights": [0.20, 0.20, 0.20, 0.20, 0.20],
        },
        "4. Con Compounding + Front-Loaded (25/20/20/20/15%)": {
            "compounding": True,
            "weights": [0.25, 0.20, 0.20, 0.20, 0.15],
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
        for name, spec in configs.items():
            cfg = BotConfig(
                bot_id="btc_test",
                symbol="BTC/USDT",
                budget=1000.0,
                take_profit_pct=5.0,
                max_tranches=5,
                tranche_weights=spec["weights"],
                atr_multiplier=1.5,
                trailing_stop_pct=2.5,
            )
            strat = CompoundingChainedStrategy(cfg, enable_compounding=spec["compounding"])
            m, _, _ = engine.run(strat, sub_df, 1000.0)
            results.append({
                "Modelo": name,
                "Retorno Total": f"{m.total_return_pct:+.2f}%",
                "Max DD": f"-{m.max_drawdown_pct:.2f}%",
                "Flujo Caja Realizado": f"${m.cash_flow_usdt:.2f}",
                "Trades": m.total_trades,
                "Win Rate": f"{m.win_rate_pct:.1f}%",
                "Sharpe": f"{m.sharpe_ratio:.2f}",
            })

        print(f"\n{'='*105}")
        print(f" BENCHMARK DE INTERÉS COMPUESTO Y ASIGNACIÓN (IGNORANDO DRAWDOWN): {sc_name}")
        print(f"{'='*105}")
        print(tabulate(results, headers="keys", tablefmt="github"))


if __name__ == "__main__":
    run_experiment()
