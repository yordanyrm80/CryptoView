import sys
from pathlib import Path

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
from src.strategies.btc_regime import BtcChainedRegimeStrategy


# ---------------------------------------------------------------------------
# VARIANTE 1: TP DINÁMICO POR ATR INSTANTÁNEO
# TP = max(2.5%, atr_pct * 2.0)
# ---------------------------------------------------------------------------
class DynamicAtrExitStrategy(BtcChainedRegimeStrategy):
    """Calcula el Take Profit al momento de comprar como función directa del ATR horario."""

    def evaluate(self, current_row: pd.Series, portfolio: PortfolioState):
        signals = super().evaluate(current_row, portfolio)
        atr_pct = max(current_row.get("atr_pct", 2.0), 1.0)
        dynamic_tp_pct = max(2.5, atr_pct * 2.2)

        # Modificar las señales de compra emitidas para asignarles el TP dinámico
        for sig in signals:
            if sig.signal_type == SignalType.BUY_TRANCHE and sig.price:
                # En tendencia fuerte ya tiene TP lejano, solo ajustar rango y sniper
                if sig.target_sell_price and sig.target_sell_price < sig.price * 1.5:
                    sig.target_sell_price = sig.price * (1.0 + dynamic_tp_pct / 100.0)

        return signals


# ---------------------------------------------------------------------------
# VARIANTE 2: TP ASIMÉTRICO CRECIENTE POR TRAMO
# T0: +3.0% (rotación rápida de entrada alta)
# T1: +4.5%
# T2: +6.5%
# T3: +9.0%
# T4: +12.0% (gran rebote tras caída profunda)
# ---------------------------------------------------------------------------
class AsymmetricAscendingExitStrategy(BtcChainedRegimeStrategy):
    """Tramos más profundos exigen mayor beneficio debido a la magnitud esperada del rebote."""

    TP_TABLE = [3.0, 4.5, 6.5, 9.0, 12.0]

    def evaluate(self, current_row: pd.Series, portfolio: PortfolioState):
        signals = super().evaluate(current_row, portfolio)
        for sig in signals:
            if sig.signal_type == SignalType.BUY_TRANCHE and sig.price:
                if sig.target_sell_price and sig.target_sell_price < sig.price * 1.5:
                    tp_pct = self.TP_TABLE[min(sig.tranche_index, len(self.TP_TABLE) - 1)]
                    sig.target_sell_price = sig.price * (1.0 + tp_pct / 100.0)
        return signals


# ---------------------------------------------------------------------------
# VARIANTE 3: TP ASIMÉTRICO DECRECIENTE / DEFENSIVO (Recuperador de Liquidez)
# T0: +5.0%
# T1: +4.0%
# T2: +3.0%
# T3: +2.5%
# T4: +2.0% (Tramo 4 solo busca recuperar el 30% del capital lo antes posible)
# ---------------------------------------------------------------------------
class AsymmetricDefensiveExitStrategy(BtcChainedRegimeStrategy):
    """Tramos profundos exigen MENOR ganancia para desatascar la liquidez rápidamente."""

    TP_TABLE = [5.0, 4.0, 3.0, 2.5, 2.0]

    def evaluate(self, current_row: pd.Series, portfolio: PortfolioState):
        signals = super().evaluate(current_row, portfolio)
        for sig in signals:
            if sig.signal_type == SignalType.BUY_TRANCHE and sig.price:
                if sig.target_sell_price and sig.target_sell_price < sig.price * 1.5:
                    tp_pct = self.TP_TABLE[min(sig.tranche_index, len(self.TP_TABLE) - 1)]
                    sig.target_sell_price = sig.price * (1.0 + tp_pct / 100.0)
        return signals


# ---------------------------------------------------------------------------
# VARIANTE 4: TRAILING TAKE PROFIT DINÁMICO EN TODOS LOS TRAMOS
# Se activa al llegar a +3.5%, y usa un trailing stop de 1.5% para dejar correr
# ---------------------------------------------------------------------------
class TrailingTakeProfitStrategy(BaseStrategy):
    """En lugar de venta fija por límite, activa trailing stop una vez superado el umbral base."""

    def __init__(self, config: BotConfig):
        super().__init__(config)
        self.tranche_highs = {}
        self.trend_highest_price = None

    def evaluate(self, current_row: pd.Series, portfolio: PortfolioState):
        signals = []
        regime = RegimeDetector.detect_regime(current_row)
        current_price = current_row["close"]
        high_price = current_row["high"]
        low_price = current_row["low"]
        atr_14 = current_row.get("atr_14", current_price * 0.02)
        rsi = current_row.get("rsi_14", 50.0)

        # Evaluar salidas con Trailing TP
        for tranche in list(portfolio.active_tranches):
            if tranche.status != TrancheStatus.ACTIVE:
                continue

            # Actualizar máximo registrado para este tramo
            t_idx = tranche.tranche_index
            if t_idx not in self.tranche_highs:
                self.tranche_highs[t_idx] = high_price
            else:
                self.tranche_highs[t_idx] = max(self.tranche_highs[t_idx], high_price)

            t_high = self.tranche_highs[t_idx]
            activation_price = tranche.buy_price * 1.035  # Activación en +3.5%

            # Si ya se superó la activación, stop dinámico al 1.5% desde el pico
            if t_high >= activation_price:
                trail_stop = t_high * 0.985
                if low_price <= trail_stop and trail_stop > tranche.buy_price * 1.01:
                    signals.append(
                        ActionSignal(
                            signal_type=SignalType.SELL_TRANCHE,
                            symbol=self.config.symbol,
                            tranche_index=tranche.tranche_index,
                            price=trail_stop,
                            amount=tranche.amount,
                            allocated_usdt=tranche.allocated_budget,
                            reason=f"Trailing TP ejecutado (+{((trail_stop/tranche.buy_price)-1)*100:.1f}%)",
                            tranche_ref=tranche,
                        )
                    )
                    self.tranche_highs.pop(t_idx, None)
                    continue

            # Salida de emergencia en bull trend
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

        # ENTRADAS: Idénticas a BtcChainedRegimeStrategy
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
                                target_sell_price=current_price * 1.5,  # Controlado por Trailing TP
                                reason="RANGO T0",
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
                                    target_sell_price=current_price * 1.5,  # Controlado por Trailing TP
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
                                reason="TENDENCIA T0",
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
                            reason="PÁNICO Sniper",
                        )
                    )

        return signals


# ---------------------------------------------------------------------------
# VARIANTE 5: TARGET EMA 50 (Reversión a la media móvil)
# ---------------------------------------------------------------------------
class MeanReversionEmaExitStrategy(BtcChainedRegimeStrategy):
    """Vende cuando el precio toca la EMA 50 o un mínimo de ganancia del +2.5%."""

    def evaluate(self, current_row: pd.Series, portfolio: PortfolioState):
        signals = super().evaluate(current_row, portfolio)
        ema_50 = current_row["ema_50"]
        for sig in signals:
            if sig.signal_type == SignalType.BUY_TRANCHE and sig.price:
                if sig.target_sell_price and sig.target_sell_price < sig.price * 1.5:
                    # Si la EMA 50 está por encima con al menos 2.5% de ganancia, usarla
                    target_ema = max(sig.price * 1.025, min(sig.price * 1.10, ema_50))
                    sig.target_sell_price = target_ema
        return signals


def run_exit_experiment():
    db = DatabaseManager("data/criptobot.db")
    repo = CandleRepository(db)

    df_raw = repo.get_candles_df("BTC/USDT", "1h")
    df = TechnicalIndicators.apply_all(df_raw)

    config = BotConfig(
        bot_id="exp_btc_exits",
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
            "1. Baseline Actual (TP Fijo 5.0%)": BtcChainedRegimeStrategy(config),
            "2. TP Dinámico por ATR Instantáneo": DynamicAtrExitStrategy(config),
            "3. TP Asimétrico Creciente (+3% a +12%)": AsymmetricAscendingExitStrategy(config),
            "4. TP Asimétrico Defensivo (+5% a +2%)": AsymmetricDefensiveExitStrategy(config),
            "5. Trailing Take Profit Dinámico": TrailingTakeProfitStrategy(config),
            "6. Reversión a Media (Target EMA 50)": MeanReversionEmaExitStrategy(config),
        }

        results = []
        for s_name, strat in strats.items():
            m, _, _ = engine.run(strat, sub_df, 1000.0)
            results.append({
                "Estrategia de Salida": s_name,
                "Retorno Total": f"{m.total_return_pct:+.2f}%",
                "Max DD": f"-{m.max_drawdown_pct:.2f}%",
                "Flujo Caja Realizado": f"${m.cash_flow_usdt:.2f}",
                "Trades": m.total_trades,
                "Win Rate": f"{m.win_rate_pct:.1f}%",
                "Días Atrapado": f"{m.max_days_trapped:.1f}d",
                "Sharpe": f"{m.sharpe_ratio:.2f}",
            })

        print(f"\n{'='*105}")
        print(f" EXPERIMENTO DE SALIDAS Y TAKE PROFIT (BTC/USDT): {sc_name}")
        print(f"{'='*105}")
        print(tabulate(results, headers="keys", tablefmt="github"))


if __name__ == "__main__":
    run_exit_experiment()
