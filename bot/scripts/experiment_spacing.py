import sys
from pathlib import Path

# Agregar raíz del proyecto al sys.path
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

import pandas as pd
import numpy as np
from tabulate import tabulate

from src.domain.models import BotConfig, MarketRegime, TrancheStatus
from src.indicators.technical import TechnicalIndicators
from src.simulation.engine import SimulationEngine
from src.storage.candle_repository import CandleRepository
from src.storage.database import DatabaseManager
from src.strategies.base import ActionSignal, BaseStrategy, PortfolioState, SignalType
from src.core.regime_detector import RegimeDetector


# ---------------------------------------------------------------------------
# VARIANTE 1: BASELINE (Actual 3 Regímenes con ATR fijo anclado a P0)
# ---------------------------------------------------------------------------
from src.strategies.three_regime import AdaptiveThreeRegimeStrategy


# ---------------------------------------------------------------------------
# VARIANTE 2: ATR RELATIVO EN CADENA (Chandelier Spacing dinámico desde último tramo)
# ---------------------------------------------------------------------------
class ChainedAtrStrategy(BaseStrategy):
    """Espaciado encadenado al precio de la última compra ejecutada, escalado con ATR dinámico actual."""

    def __init__(self, config: BotConfig):
        super().__init__(config)
        self.trend_highest_price = None

    def evaluate(self, current_row: pd.Series, portfolio: PortfolioState):
        signals = []
        regime = RegimeDetector.detect_regime(current_row)
        current_price = current_row["close"]
        high_price = current_row["high"]
        low_price = current_row["low"]
        atr_14 = current_row.get("atr_14", current_price * 0.02)
        rsi = current_row.get("rsi_14", 50.0)

        # Evaluar salidas
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
                        reason=f"TP alcanzado ({tranche.target_sell_price:.2f})",
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
                            reason=f"Trailing Stop ejecutado",
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
                                reason="Régimen RANGO: Entrada T0",
                            )
                        )
            else:
                # Compras encadenadas: el siguiente tramo compra a N ATRs por debajo del tramo anterior
                highest_idx = max(occupied.keys())
                next_idx = highest_idx + 1
                if next_idx < self.config.max_tranches:
                    last_buy_price = occupied[highest_idx].buy_price
                    # Multiplicadores de ATR crecientes según el tramo
                    # T1: 2.0 ATR, T2: 3.5 ATR, T3: 5.5 ATR, T4: 8.0 ATR
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
                                    reason=f"RANGO: Entrada T{next_idx} encadenada (-{required_drop:.2f} USDT)",
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
                                reason="TENDENCIA: Entrada en retroceso",
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
                            target_sell_price=current_price * 1.07,
                            reason="PÁNICO: Francotirador RSI < 25",
                        )
                    )

        return signals


# ---------------------------------------------------------------------------
# VARIANTE 3: MOMENTUM EXHAUSTION (ATR Dinámico + RSI Escalonado)
# Exige que el RSI esté en sobreventa severa creciente antes de comprar tramos bajos
# ---------------------------------------------------------------------------
class ExhaustionMomentumStrategy(BaseStrategy):
    """Combina distancia de ATR con niveles escalonados de sobreventa RSI extrema."""

    def __init__(self, config: BotConfig):
        super().__init__(config)
        self.reference_price = None
        self.trend_highest_price = None

    def evaluate(self, current_row: pd.Series, portfolio: PortfolioState):
        signals = []
        regime = RegimeDetector.detect_regime(current_row)
        current_price = current_row["close"]
        high_price = current_row["high"]
        low_price = current_row["low"]
        atr_pct = max(current_row.get("atr_pct", 2.0), 1.5)
        rsi = current_row.get("rsi_14", 50.0)

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
                        reason=f"TP alcanzado ({tranche.target_sell_price:.2f})",
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
                            reason=f"Trailing Stop",
                            tranche_ref=tranche,
                        )
                    )
                    self.trend_highest_price = None

        if signals:
            return signals

        occupied = {t.tranche_index: t for t in portfolio.active_tranches if t.status == TrancheStatus.ACTIVE}

        if regime == MarketRegime.RANGE:
            step_pct = max(3.0, atr_pct * self.config.atr_multiplier)

            if len(occupied) == 0:
                self.reference_price = current_price
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
                                reason="Régimen RANGO: Entrada T0",
                            )
                        )
            elif self.reference_price is not None:
                # Multiplicadores ampliados y RSI escalonado
                multipliers = [1.0, 2.5, 5.0, 9.0]
                rsi_max_thresholds = [45.0, 35.0, 26.0, 20.0]

                for idx in range(1, self.config.max_tranches):
                    if idx not in occupied:
                        mult = multipliers[idx - 1]
                        drop_required = step_pct * mult
                        target_buy = self.reference_price * (1.0 - drop_required / 100.0)
                        max_rsi = rsi_max_thresholds[idx - 1]

                        if current_price <= target_buy and rsi <= max_rsi:
                            budget_t = self.config.budget * self.config.tranche_weights[idx]
                            if portfolio.available_usdt >= budget_t:
                                signals.append(
                                    ActionSignal(
                                        signal_type=SignalType.BUY_TRANCHE,
                                        symbol=self.config.symbol,
                                        tranche_index=idx,
                                        price=current_price,
                                        amount=budget_t / current_price,
                                        allocated_usdt=budget_t,
                                        target_sell_price=current_price * (1.0 + self.config.take_profit_pct / 100.0),
                                        reason=f"T{idx} por Agotamiento: Drop -{drop_required:.1f}% & RSI {rsi:.1f} <= {max_rsi}",
                                    )
                                )
                                break

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
                                reason="TENDENCIA: Entrada",
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
                            target_sell_price=current_price * 1.07,
                            reason="PÁNICO: Francotirador",
                        )
                    )

        return signals


# ---------------------------------------------------------------------------
# VARIANTE 4: ESTRUCTURAL / FRACTAL (Donchian Support Levels)
# Compra en los mínimos históricos de 24h, 72h, 168h (1 semana) y 720h (1 mes)
# ---------------------------------------------------------------------------
class StructuralDonchianStrategy(BaseStrategy):
    """Espaciado determinado por los niveles mínimos estructurales de Donchian."""

    def __init__(self, config: BotConfig):
        super().__init__(config)
        self.trend_highest_price = None

    def evaluate(self, current_row: pd.Series, portfolio: PortfolioState):
        signals = []
        regime = RegimeDetector.detect_regime(current_row)
        current_price = current_row["close"]
        high_price = current_row["high"]
        low_price = current_row["low"]
        rsi = current_row.get("rsi_14", 50.0)

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
                        reason=f"TP alcanzado",
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
                            reason=f"Trailing Stop",
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
                                reason="Régimen RANGO: Entrada T0",
                            )
                        )
            else:
                support_levels = [
                    current_row.get("donchian_low_24", current_price * 0.96),
                    current_row.get("donchian_low_72", current_price * 0.92),
                    current_row.get("donchian_low_168", current_price * 0.85),
                    current_row.get("donchian_low_720", current_price * 0.70),
                ]

                min_active_buy_price = min(t.buy_price for t in occupied.values())

                for idx in range(1, self.config.max_tranches):
                    if idx not in occupied:
                        level = support_levels[idx - 1]
                        if current_price <= level and current_price <= min_active_buy_price * 0.975:
                            budget_t = self.config.budget * self.config.tranche_weights[idx]
                            if portfolio.available_usdt >= budget_t:
                                signals.append(
                                    ActionSignal(
                                        signal_type=SignalType.BUY_TRANCHE,
                                        symbol=self.config.symbol,
                                        tranche_index=idx,
                                        price=current_price,
                                        amount=budget_t / current_price,
                                        allocated_usdt=budget_t,
                                        target_sell_price=current_price * (1.0 + self.config.take_profit_pct / 100.0),
                                        reason=f"Soporte Estructural T{idx} en {level:.2f}",
                                    )
                                )
                                break

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
                                reason="TENDENCIA: Entrada",
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
                            target_sell_price=current_price * 1.07,
                            reason="PÁNICO: Francotirador",
                        )
                    )

        return signals


# ---------------------------------------------------------------------------
# VARIANTE 5: EXPONENTIAL DEEP CRASH SHIELD (Escalado geométrico amplio)
# Diseñado para cubrir caídas macro de hasta -60% sin quedarse ilíquido a medio camino
# ---------------------------------------------------------------------------
class DeepCrashShieldStrategy(BaseStrategy):
    """Espaciado con cobertura profunda: T1 -5%, T2 -14%, T3 -30%, T4 -55%."""

    def __init__(self, config: BotConfig):
        super().__init__(config)
        self.reference_price = None
        self.trend_highest_price = None

    def evaluate(self, current_row: pd.Series, portfolio: PortfolioState):
        signals = []
        regime = RegimeDetector.detect_regime(current_row)
        current_price = current_row["close"]
        high_price = current_row["high"]
        low_price = current_row["low"]
        atr_pct = max(current_row.get("atr_pct", 2.0), 1.5)
        rsi = current_row.get("rsi_14", 50.0)

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
                        reason=f"TP alcanzado",
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
                            reason=f"Trailing Stop",
                            tranche_ref=tranche,
                        )
                    )
                    self.trend_highest_price = None

        if signals:
            return signals

        occupied = {t.tranche_index: t for t in portfolio.active_tranches if t.status == TrancheStatus.ACTIVE}

        if regime == MarketRegime.RANGE:
            if len(occupied) == 0:
                self.reference_price = current_price
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
                                reason="Régimen RANGO: Entrada T0",
                            )
                        )
            elif self.reference_price is not None:
                # Escalado con amortiguación profunda:
                # T1: -1.5 ATR (~5%)
                # T2: -4.0 ATR (~14%)
                # T3: -8.5 ATR (~30%)
                # T4: -16.0 ATR (~55%) -> Reserva para Crash Extremo
                step_pct = max(3.0, atr_pct * self.config.atr_multiplier)
                multipliers = [1.2, 3.5, 7.5, 14.0]

                for idx in range(1, self.config.max_tranches):
                    if idx not in occupied:
                        mult = multipliers[idx - 1]
                        drop_required = step_pct * mult
                        target_buy = self.reference_price * (1.0 - drop_required / 100.0)

                        if current_price <= target_buy:
                            budget_t = self.config.budget * self.config.tranche_weights[idx]
                            if portfolio.available_usdt >= budget_t:
                                signals.append(
                                    ActionSignal(
                                        signal_type=SignalType.BUY_TRANCHE,
                                        symbol=self.config.symbol,
                                        tranche_index=idx,
                                        price=current_price,
                                        amount=budget_t / current_price,
                                        allocated_usdt=budget_t,
                                        target_sell_price=current_price * (1.0 + self.config.take_profit_pct / 100.0),
                                        reason=f"RANGO: Entrada T{idx} Deep Crash (-{drop_required:.1f}%)",
                                    )
                                )
                                break

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
                                reason="TENDENCIA: Entrada",
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
                            target_sell_price=current_price * 1.07,
                            reason="PÁNICO: Francotirador",
                        )
                    )

        return signals


def run_experiment():
    db = DatabaseManager("data/criptobot.db")
    repo = CandleRepository(db)

    # Cargar datos de BTC/USDT (6 años completos)
    df_raw = repo.get_candles_df("BTC/USDT", "1h")
    df = TechnicalIndicators.apply_all(df_raw)

    # Añadir soportes Donchian adicionales
    df["donchian_low_72"] = df["low"].rolling(window=72).min()
    df["donchian_low_168"] = df["low"].rolling(window=168).min()
    df["donchian_low_720"] = df["low"].rolling(window=720).min()

    config = BotConfig(
        bot_id="exp_btc",
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
    }

    engine = SimulationEngine(fee_rate=0.001, enable_profit_recycling=True)

    for sc_name, (start_ts, end_ts) in scenarios.items():
        if start_ts is not None and end_ts is not None:
            sub_df = df[(df["timestamp"] >= start_ts) & (df["timestamp"] <= end_ts)].copy()
        else:
            sub_df = df.copy()

        strats = {
            "1. Baseline (ATR P0)": AdaptiveThreeRegimeStrategy(config),
            "2. ATR Chained (Encadenado)": ChainedAtrStrategy(config),
            "3. Exhaustion (ATR+RSI Extremo)": ExhaustionMomentumStrategy(config),
            "4. Donchian Estructural": StructuralDonchianStrategy(config),
            "5. Deep Crash Shield": DeepCrashShieldStrategy(config),
        }

        results = []
        for s_name, strat in strats.items():
            m, _, _ = engine.run(strat, sub_df, 1000.0)
            results.append({
                "Estrategia": s_name,
                "Retorno Total": f"{m.total_return_pct:+.2f}%",
                "Max DD": f"-{m.max_drawdown_pct:.2f}%",
                "Flujo Caja Realizado": f"${m.cash_flow_usdt:.2f}",
                "Trades": m.total_trades,
                "Win Rate": f"{m.win_rate_pct:.1f}%",
                "Días Atrapado": f"{m.max_days_trapped:.1f}d",
                "Sharpe": f"{m.sharpe_ratio:.2f}",
            })

        print(f"\n{'='*95}")
        print(f" EXPERIMENTO DE ESPACIADO: {sc_name}")
        print(f"{'='*95}")
        print(tabulate(results, headers="keys", tablefmt="github"))


if __name__ == "__main__":
    run_experiment()
