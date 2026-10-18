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
from src.strategies.btc_regime import BtcChainedRegimeStrategy


# ---------------------------------------------------------------------------
# MEJORA 1: FILTRO ANTI-EUFORIA PARABÓLICA
# No abrir Tramo 0 si el precio está a más del 20% por encima de la EMA 200
# ---------------------------------------------------------------------------
class AntiEuphoriaStrategy(BtcChainedRegimeStrategy):
    def evaluate(self, current_row: pd.Series, portfolio: PortfolioState):
        signals = []
        regime = RegimeDetector.detect_regime(current_row)
        current_price = current_row["close"]
        high_price = current_row["high"]
        low_price = current_row["low"]
        atr_14 = current_row.get("atr_14", current_price * 0.02)
        rsi = current_row.get("rsi_14", 50.0)
        ema_200 = current_row["ema_200"]

        # Salidas
        for tranche in list(portfolio.active_tranches):
            if tranche.status != TrancheStatus.ACTIVE:
                continue
            if high_price >= tranche.target_sell_price:
                signals.append(
                    ActionSignal(
                        signal_type=SignalType.SELL_TRANCHE,
                        symbol=self.config.symbol,
                        tranche_index=tranche.tranche_index,
                        price=tranche.target_sell_price,
                        amount=tranche.amount,
                        allocated_usdt=tranche.allocated_budget,
                        reason="TP alcanzado",
                        tranche_ref=tranche,
                    )
                )
                continue
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

        occupied = {t.tranche_index: t for t in portfolio.active_tranches if t.status == TrancheStatus.ACTIVE}

        if regime == MarketRegime.RANGE:
            if len(occupied) == 0:
                # FILTRO ANTI-EUFORIA: Debe estar >= EMA 200 pero <= 1.20 * EMA 200
                if ema_200 <= current_price <= ema_200 * 1.20 and rsi < 48.0:
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
                                reason="RANGO T0 Anti-Euforia",
                            )
                        )
            else:
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
                    budget_trend = self.config.budget * 0.40
                    if portfolio.available_usdt >= budget_trend:
                        self.trend_highest_price = high_price
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


# ---------------------------------------------------------------------------
# MEJORA 2: FILTRO DE COOLDOWN / HISTÉRESIS TRAS VENTA
# No comprar Tramo 0 inmediatamente tras un Take Profit si el precio no retrocede al menos 1.5 ATR
# ---------------------------------------------------------------------------
class CooldownStrategy(BtcChainedRegimeStrategy):
    def __init__(self, config: BotConfig):
        super().__init__(config)
        self.last_sell_price: Optional[float] = None

    def evaluate(self, current_row: pd.Series, portfolio: PortfolioState):
        signals = []
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
            if high_price >= tranche.target_sell_price:
                self.last_sell_price = tranche.target_sell_price
                signals.append(
                    ActionSignal(
                        signal_type=SignalType.SELL_TRANCHE,
                        symbol=self.config.symbol,
                        tranche_index=tranche.tranche_index,
                        price=tranche.target_sell_price,
                        amount=tranche.amount,
                        allocated_usdt=tranche.allocated_budget,
                        reason="TP alcanzado",
                        tranche_ref=tranche,
                    )
                )
                continue
            if regime == MarketRegime.BULL_TREND and self.trend_highest_price is not None:
                if high_price > self.trend_highest_price:
                    self.trend_highest_price = high_price
                stop_price = self.trend_highest_price * (1.0 - self.config.trailing_stop_pct / 100.0)
                if tranche.buy_price and stop_price > tranche.buy_price and low_price <= stop_price:
                    self.last_sell_price = stop_price
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

        occupied = {t.tranche_index: t for t in portfolio.active_tranches if t.status == TrancheStatus.ACTIVE}

        if regime == MarketRegime.RANGE:
            if len(occupied) == 0:
                ema_200 = current_row["ema_200"]
                # FILTRO COOLDOWN: Si vendió recientemente, debe retroceder al menos 1.2 * ATR desde la venta
                cooldown_ok = True
                if self.last_sell_price is not None:
                    if current_price > (self.last_sell_price - atr_14 * 1.2):
                        cooldown_ok = False

                if current_price >= ema_200 and rsi < 48.0 and cooldown_ok:
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
                                reason="RANGO T0 con Cooldown",
                            )
                        )
            else:
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
                    budget_trend = self.config.budget * 0.40
                    if portfolio.available_usdt >= budget_trend:
                        self.trend_highest_price = high_price
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


def run_benchmark():
    db = DatabaseManager("data/criptobot.db")
    repo = CandleRepository(db)
    df_raw = repo.get_candles_df("BTC/USDT", "1h")
    df = TechnicalIndicators.apply_all(df_raw)

    config_base = BotConfig(
        bot_id="btc_base",
        symbol="BTC/USDT",
        budget=1000.0,
        take_profit_pct=5.0,
        max_tranches=5,
        tranche_weights=[0.10, 0.15, 0.20, 0.25, 0.30],
        atr_multiplier=1.5,
        trailing_stop_pct=2.5,
    )

    config_flat = BotConfig(
        bot_id="btc_flat",
        symbol="BTC/USDT",
        budget=1000.0,
        take_profit_pct=5.0,
        max_tranches=5,
        tranche_weights=[0.20, 0.20, 0.20, 0.20, 0.20],
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
    }

    engine = SimulationEngine(fee_rate=0.001, enable_profit_recycling=True)

    for sc_name, (start_ts, end_ts) in scenarios.items():
        if start_ts is not None and end_ts is not None:
            sub_df = df[(df["timestamp"] >= start_ts) & (df["timestamp"] <= end_ts)].copy()
        else:
            sub_df = df.copy()

        strats = {
            "1. Baseline Actual (5 Tramos Escalonados)": BtcChainedRegimeStrategy(config_base),
            "2. Pesos Planos (5 Tramos 20% cada uno)": BtcChainedRegimeStrategy(config_flat),
            "3. Filtro Anti-Euforia (Max 1.20*EMA200)": AntiEuphoriaStrategy(config_base),
            "4. Filtro Cooldown post-TP (Retroceso 1.2 ATR)": CooldownStrategy(config_base),
        }

        results = []
        for s_name, strat in strats.items():
            m, _, _ = engine.run(strat, sub_df, 1000.0)
            results.append({
                "Estrategia / Hipótesis": s_name,
                "Retorno Total": f"{m.total_return_pct:+.2f}%",
                "Max DD": f"-{m.max_drawdown_pct:.2f}%",
                "Flujo Caja": f"${m.cash_flow_usdt:.2f}",
                "Trades": m.total_trades,
                "Win Rate": f"{m.win_rate_pct:.1f}%",
                "Días Atrapado": f"{m.max_days_trapped:.1f}d",
                "Sharpe": f"{m.sharpe_ratio:.2f}",
            })

        print(f"\n{'='*105}")
        print(f" EVALUACIÓN DE PUNTOS DE MEJORA: {sc_name}")
        print(f"{'='*105}")
        print(tabulate(results, headers="keys", tablefmt="github"))


if __name__ == "__main__":
    run_benchmark()
