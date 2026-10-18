from typing import List, Optional, Tuple
import pandas as pd
from src.domain.models import Tranche, TrancheStatus
from src.simulation.metrics import MetricsCalculator, SimulationMetrics
from src.strategies.base import BaseStrategy, PortfolioState, SignalType


class SimulationEngine:
    """Candle-by-candle quantitative backtesting engine with realistic fees and profit recycling."""

    def __init__(
        self,
        fee_rate: float = 0.001,
        maker_fee: Optional[float] = None,
        stop_slippage: float = 0.0005,
        enable_profit_recycling: bool = True,
        allow_subsidized_discount: bool = True,
        max_subsidized_discount_pct: float = 0.12,
        recycle_profit_fraction: float = 0.35,
        enable_cascading_discount: bool = True,
        satoshi_recycling: bool = False,
        harvest_mode: str = "USDT",
    ):
        self.fee_rate = maker_fee if maker_fee is not None else fee_rate
        self.maker_fee = self.fee_rate
        self.stop_slippage = stop_slippage
        self.enable_profit_recycling = enable_profit_recycling
        self.allow_subsidized_discount = allow_subsidized_discount
        self.max_subsidized_discount_pct = max_subsidized_discount_pct
        self.recycle_profit_fraction = recycle_profit_fraction
        self.enable_cascading_discount = enable_cascading_discount
        self.satoshi_recycling = satoshi_recycling
        self.harvest_mode = harvest_mode

    def run(
        self,
        strategy: BaseStrategy,
        df_candles: pd.DataFrame,
        initial_capital: float = 1000.0,
        capital_injections: Optional[List[Tuple[int, float]]] = None,
    ) -> Tuple[SimulationMetrics, pd.Series, List[Tranche]]:
        strat = strategy
        df_c = df_candles.copy()
        if not isinstance(df_c.index, pd.DatetimeIndex):
            if "timestamp" in df_c.columns:
                df_c.index = pd.to_datetime(df_c["timestamp"], unit="ms", utc=True)

        portfolio = PortfolioState(
            symbol=strat.config.symbol,
            total_budget=initial_capital,
            available_usdt=initial_capital,
            active_tranches=[],
            completed_tranches=[],
            total_realized_profit=0.0,
            total_withdrawn_amount=0.0,
            total_deposited_amount=0.0,
        )

        injections = sorted(capital_injections or [], key=lambda x: x[0])
        injection_idx = 0

        total_deposited_capital = initial_capital
        equity_records = []
        timestamps = []

        for idx, row in df_c.iterrows():
            current_ts = int(row["timestamp"]) if "timestamp" in row else int(idx.timestamp() * 1000)
            close_price = row["close"]

            # Capital Injections
            while injection_idx < len(injections) and current_ts >= injections[injection_idx][0]:
                _, amount = injections[injection_idx]
                portfolio.available_usdt += amount
                portfolio.total_budget += amount
                portfolio.total_deposited_amount += amount
                total_deposited_capital += amount
                injection_idx += 1

            # Evaluate strategy signals
            signals = strat.evaluate(row, portfolio)

            # Process sell signals first
            for sig in signals:
                if sig.signal_type == SignalType.SELL_TRANCHE and sig.tranche_ref is not None:
                    tranche = sig.tranche_ref
                    if tranche in portfolio.active_tranches:
                        nominal_price = sig.price
                        is_trailing = "Trailing Stop" in (sig.reason or "")
                        if is_trailing and self.stop_slippage > 0:
                            actual_executed_price = nominal_price * (1.0 - self.stop_slippage)
                            fee_rate = self.fee_rate
                        else:
                            actual_executed_price = nominal_price
                            fee_rate = self.fee_rate

                        revenue_gross = tranche.amount * actual_executed_price
                        sell_fee = revenue_gross * fee_rate
                        revenue_net = revenue_gross - sell_fee

                        cost_basis = tranche.allocated_budget + (tranche.buy_fee or 0.0)
                        realized_profit = revenue_net - cost_basis

                        tranche.actual_sell_price = actual_executed_price
                        tranche.sell_fee = sell_fee
                        tranche.sell_timestamp = current_ts
                        tranche.profit_usdt = realized_profit
                        tranche.status = TrancheStatus.CLOSED

                        portfolio.available_usdt += revenue_net
                        portfolio.total_realized_profit += realized_profit
                        portfolio.completed_tranches.append(tranche)
                        portfolio.active_tranches.remove(tranche)

                        # Per-trade cascading subsidized profit recycling
                        if (
                            self.enable_profit_recycling
                            and self.allow_subsidized_discount
                            and realized_profit > 0
                            and portfolio.active_tranches
                        ):
                            remaining_discount = realized_profit * self.recycle_profit_fraction
                            hung_tranches = [
                                t for t in portfolio.active_tranches if t.buy_price > tranche.buy_price
                            ]
                            hung_tranches.sort(key=lambda t: t.buy_price, reverse=True)
                            for target_tranche in hung_tranches:
                                if remaining_discount <= 0.001:
                                    break
                                floor_min = target_tranche.buy_price * (1.0 - self.max_subsidized_discount_pct)
                                max_reduction = target_tranche.target_sell_price - floor_min
                                if max_reduction <= 0:
                                    continue
                                max_absorbable_usdt = max_reduction * target_tranche.amount
                                apply_discount = min(remaining_discount, max_absorbable_usdt)
                                target_tranche.target_sell_price -= apply_discount / target_tranche.amount
                                remaining_discount -= apply_discount

                        if self.enable_profit_recycling and realized_profit > 0 and self.satoshi_recycling and self.harvest_mode == "SATOSHIS":
                            recycled_cut = realized_profit * self.recycle_profit_fraction
                            satoshis = recycled_cut / actual_executed_price
                            portfolio.subsidized_satoshis_total += satoshis
                            portfolio.harvested_btc_free += satoshis

            # Process buy signals second
            for sig in signals:
                if sig.signal_type == SignalType.BUY_TRANCHE:
                    already_bought = any(
                        t.tranche_index == sig.tranche_index and t.status == TrancheStatus.ACTIVE
                        for t in portfolio.active_tranches
                    )
                    if not already_bought:
                        cost = sig.allocated_usdt
                        if portfolio.available_usdt >= cost and cost > 0:
                            buy_fee = cost * self.fee_rate
                            if portfolio.available_usdt >= (cost + buy_fee):
                                portfolio.available_usdt -= (cost + buy_fee)
                                buy_price = sig.price
                                amount = cost / buy_price

                                target_sell = sig.target_sell_price or (buy_price * (1.0 + strat.config.take_profit_pct / 100.0))

                                new_tranche = Tranche(
                                    bot_id=strat.config.bot_id,
                                    symbol=strat.config.symbol,
                                    tranche_index=sig.tranche_index,
                                    allocated_budget=cost,
                                    buy_price=buy_price,
                                    amount=amount,
                                    target_sell_price=target_sell,
                                    status=TrancheStatus.ACTIVE,
                                    buy_fee=buy_fee,
                                    buy_timestamp=current_ts,
                                )
                                portfolio.active_tranches.append(new_tranche)

            # Record mark-to-market equity
            unrealized_crypto_val = sum(
                t.amount * close_price for t in portfolio.active_tranches
            )
            harvested_btc_val = portfolio.harvested_btc_free * close_price
            total_equity = portfolio.available_usdt + unrealized_crypto_val + harvested_btc_val
            equity_records.append(total_equity)
            timestamps.append(idx)

        equity_series = pd.Series(equity_records, index=timestamps)

        metrics = MetricsCalculator.calculate(
            strategy_name=strat.__class__.__name__,
            symbol=strat.config.symbol,
            initial_capital=total_deposited_capital,
            equity_series=equity_series,
            completed_tranches=portfolio.completed_tranches,
            active_tranches=portfolio.active_tranches,
            candles_df=df_c,
            fee_rate=self.fee_rate,
            accumulated_satoshis=portfolio.subsidized_satoshis_total,
            free_harvested_btc=portfolio.harvested_btc_free,
        )

        return metrics, equity_series, portfolio.completed_tranches

    def execute(self, strategy: BaseStrategy, df_candles: pd.DataFrame, initial_capital: float = 1000.0, **kwargs):
        return self.run(strategy, df_candles, initial_capital=initial_capital, **kwargs)

    def ejecutar(self, estrategia, df_velas, capital_inicial=1000.0, **kwargs):
        return self.run(estrategia, df_velas, initial_capital=capital_inicial, **kwargs)
