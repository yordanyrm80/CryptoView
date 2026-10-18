import sys
from pathlib import Path

# Agregar raíz del proyecto
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
from src.strategies.btc_regime import BtcChainedRegimeStrategy


class BtcHybridExitStrategy(BaseStrategy):
    """Estrategia BTC con Chained ATR y Salidas Quirúrgicas Asimétricas:
    - Modo Rango (Macro alcista / neutro >= EMA 200): TP óptimo al +5.0%
    - Modo Bajista / Distress (< EMA 200 o Tramos Profundos T3/T4): TP rápido de alivio al +3.5%
    - Modo Pánico Capitulación: Disparo Francotirador con TP rápido al +3.5%
    - Modo Tendencia Alcista Fuerte: Trailing Stop dinámico al 2.5% desde el pico
    """

    def __init__(self, config: BotConfig):
        super().__init__(config)
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
        ema_200 = current_row["ema_200"]

        # -------------------------------------------------------------
        # 1. EVALUACIÓN DE SALIDAS
        # -------------------------------------------------------------
        for tranche in list(portfolio.active_tranches):
            if tranche.status != TrancheStatus.ACTIVE:
                continue

            # A) Salida por Take Profit Estándar
            if high_price >= tranche.target_sell_price:
                signals.append(
                    ActionSignal(
                        signal_type=SignalType.SELL_TRANCHE,
                        symbol=self.config.symbol,
                        tranche_index=tranche.tranche_index,
                        price=tranche.target_sell_price,
                        amount=tranche.amount,
                        allocated_usdt=tranche.allocated_budget,
                        reason=f"Take Profit alcanzado ({tranche.target_sell_price:.2f})",
                        tranche_ref=tranche,
                    )
                )
                continue

            # B) Salida por Trailing Stop en Tendencia Alcista Fuerte
            if regime == MarketRegime.BULL_TREND and self.trend_highest_price is not None:
                if high_price > self.trend_highest_price:
                    self.trend_highest_price = high_price

                stop_price = self.trend_highest_price * (1.0 - self.config.trailing_stop_pct / 100.0)
                if tranche.buy_price and stop_price > tranche.buy_price:
                    if low_price <= stop_price:
                        signals.append(
                            ActionSignal(
                                signal_type=SignalType.SELL_TRANCHE,
                                symbol=self.config.symbol,
                                tranche_index=tranche.tranche_index,
                                price=stop_price,
                                amount=tranche.amount,
                                allocated_usdt=tranche.allocated_budget,
                                reason=f"Trailing Stop ejecutado (+{((stop_price/tranche.buy_price)-1)*100:.1f}%)",
                                tranche_ref=tranche,
                            )
                        )
                        self.trend_highest_price = None

        if signals:
            return signals

        # -------------------------------------------------------------
        # 2. EVALUACIÓN DE ENTRADAS SEGÚN RÉGIMEN
        # -------------------------------------------------------------
        occupied = {t.tranche_index: t for t in portfolio.active_tranches if t.status == TrancheStatus.ACTIVE}

        # RÉGIMEN 1: MERCADO LATERAL / RANGO (~70% del tiempo)
        if regime == MarketRegime.RANGE:
            if len(occupied) == 0:
                # Filtro macro innegociable para T0: Precio >= EMA 200 y RSI sano (< 48)
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
                                target_sell_price=current_price * 1.05,  # TP 5.0% óptimo en rango
                                reason="Régimen RANGO: Entrada T0 macro sana",
                            )
                        )
            else:
                # COMPRAS ENCADENADAS
                highest_idx = max(occupied.keys())
                next_idx = highest_idx + 1

                if next_idx < self.config.max_tranches:
                    last_buy_price = occupied[highest_idx].buy_price
                    atr_mults = [2.0, 3.5, 5.5, 8.0]
                    required_drop = atr_14 * atr_mults[next_idx - 1]
                    target_buy = last_buy_price - required_drop

                    if current_price <= target_buy:
                        budget_t = self.config.budget * self.config.tranche_weights[next_idx]
                        if portfolio.available_usdt >= budget_t:
                            # Tramos 1 y 2: TP 5.0%
                            # Tramos 3 y 4 (o si el precio cayó por debajo de EMA 200): TP Rápido 3.5% para rescatar liquidez
                            tp_pct = 3.5 if (next_idx >= 3 or current_price < ema_200) else 5.0
                            target_sell = current_price * (1.0 + tp_pct / 100.0)

                            signals.append(
                                ActionSignal(
                                    signal_type=SignalType.BUY_TRANCHE,
                                    symbol=self.config.symbol,
                                    tranche_index=next_idx,
                                    price=current_price,
                                    amount=budget_t / current_price,
                                    allocated_usdt=budget_t,
                                    target_sell_price=target_sell,
                                    reason=f"RANGO BTC: Entrada T{next_idx} encadenada (TP +{tp_pct}%)",
                                )
                            )

        # RÉGIMEN 2: TENDENCIA ALCISTA FUERTE
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
                                reason="TENDENCIA BTC: Entrada con Trailing Stop",
                            )
                        )

        # RÉGIMEN 3: PÁNICO / CAPITULACIÓN
        elif regime == MarketRegime.PANIC_CAPITULATION:
            if len(occupied) == 0 and rsi < 25.0:
                budget_sniper = self.config.budget * 0.35
                if portfolio.available_usdt >= budget_sniper:
                    # Rebote rápido de alivio: +3.5% para salir de inmediato sin atascarse
                    signals.append(
                        ActionSignal(
                            signal_type=SignalType.BUY_TRANCHE,
                            symbol=self.config.symbol,
                            tranche_index=0,
                            price=current_price,
                            amount=budget_sniper / current_price,
                            allocated_usdt=budget_sniper,
                            target_sell_price=current_price * 1.035,
                            reason="PÁNICO BTC: Francotirador con TP rápido +3.5%",
                        )
                    )

        return signals


def run_benchmark():
    db = DatabaseManager("data/criptobot.db")
    repo = CandleRepository(db)
    df_raw = repo.get_candles_df("BTC/USDT", "1h")
    df = TechnicalIndicators.apply_all(df_raw)

    config = BotConfig(
        bot_id="exp_btc_hybrid",
        symbol="BTC/USDT",
        budget=1000.0,
        take_profit_pct=5.0,
        max_tranches=5,
        tranche_weights=[0.10, 0.15, 0.20, 0.25, 0.30],
        atr_multiplier=1.5,
        trailing_stop_pct=2.5,
    )

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
        "4. Mercado Bajista Reciente (2025-2026)": (
            int(pd.Timestamp("2025-09-01", tz="UTC").timestamp() * 1000),
            int(pd.Timestamp("2026-09-01", tz="UTC").timestamp() * 1000),
        ),
    }

    engine = SimulationEngine(fee_rate=0.001, enable_profit_recycling=True)

    for sc_name, (start_ts, end_ts) in scenarios.items():
        if start_ts is not None and end_ts is not None:
            sub_df = df[(df["timestamp"] >= start_ts) & (df["timestamp"] <= end_ts)].copy()
        else:
            sub_df = df.copy()

        strat_current = BtcChainedRegimeStrategy(config)
        strat_hybrid = BtcHybridExitStrategy(config)

        m_curr, _, _ = engine.run(strat_current, sub_df, 1000.0)
        m_hyb, _, _ = engine.run(strat_hybrid, sub_df, 1000.0)

        results = [
            {
                "Estrategia": "BTC Chained ATR (TP Fijo 5%)",
                "Retorno Total": f"{m_curr.total_return_pct:+.2f}%",
                "Max DD": f"-{m_curr.max_drawdown_pct:.2f}%",
                "Flujo Caja Realizado": f"${m_curr.cash_flow_usdt:.2f}",
                "Trades": m_curr.total_trades,
                "Win Rate": f"{m_curr.win_rate_pct:.1f}%",
                "Días Atrapado": f"{m_curr.max_days_trapped:.1f}d",
                "Sharpe": f"{m_curr.sharpe_ratio:.2f}",
            },
            {
                "Estrategia": "BTC Híbrida (TP 5% Rango / 3.5% Pánico-Distress)",
                "Retorno Total": f"{m_hyb.total_return_pct:+.2f}%",
                "Max DD": f"-{m_hyb.max_drawdown_pct:.2f}%",
                "Flujo Caja Realizado": f"${m_hyb.cash_flow_usdt:.2f}",
                "Trades": m_hyb.total_trades,
                "Win Rate": f"{m_hyb.win_rate_pct:.1f}%",
                "Días Atrapado": f"{m_hyb.max_days_trapped:.1f}d",
                "Sharpe": f"{m_hyb.sharpe_ratio:.2f}",
            },
        ]

        print(f"\n{'='*105}")
        print(f" BENCHMARK: {sc_name}")
        print(f"{'='*105}")
        print(tabulate(results, headers="keys", tablefmt="github"))


if __name__ == "__main__":
    run_benchmark()
