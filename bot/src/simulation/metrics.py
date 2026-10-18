from dataclasses import dataclass
from typing import List, Optional
import numpy as np
import pandas as pd


@dataclass
class SimulationMetrics:
    """Quantitative performance and risk metrics."""
    strategy_name: str
    symbol: str
    initial_capital: float
    final_equity: float
    net_profit_usdt: float
    total_return_pct: float
    buy_and_hold_return_pct: float
    max_drawdown_pct: float
    total_trades: int
    winning_trades: int
    losing_trades: int
    win_rate_pct: float
    profit_factor: float
    total_fees_paid: float
    cash_flow_usdt: float
    max_days_trapped: float
    sharpe_ratio: float
    accumulated_satoshis: float = 0.0
    free_harvested_btc: float = 0.0


class MetricsCalculator:
    """Institutional-grade backtest performance calculator."""

    @staticmethod
    def calculate(
        strategy_name: str,
        symbol: str,
        initial_capital: float,
        equity_series: pd.Series,
        completed_tranches: list,
        active_tranches: list,
        candles_df: pd.DataFrame,
        fee_rate: float = 0.001,
        accumulated_satoshis: float = 0.0,
        free_harvested_btc: float = 0.0,
    ) -> SimulationMetrics:
        final_equity = equity_series.iloc[-1] if not equity_series.empty else initial_capital
        net_profit_usdt = final_equity - initial_capital
        total_return_pct = (net_profit_usdt / initial_capital) * 100.0 if initial_capital > 0 else 0.0

        # Buy & Hold Return
        if not candles_df.empty:
            p_start = candles_df["close"].iloc[0]
            p_end = candles_df["close"].iloc[-1]
            buy_and_hold_return_pct = ((p_end - p_start) / p_start) * 100.0
        else:
            buy_and_hold_return_pct = 0.0

        # Maximum Drawdown (Peak to Trough)
        if not equity_series.empty:
            rolling_max = equity_series.cummax()
            drawdowns = (equity_series - rolling_max) / rolling_max
            max_drawdown_pct = abs(float(drawdowns.min())) * 100.0
        else:
            max_drawdown_pct = 0.0

        # Trade metrics
        total_trades = len(completed_tranches)
        winning_trades = sum(1 for t in completed_tranches if t.profit_usdt > 0)
        losing_trades = sum(1 for t in completed_tranches if t.profit_usdt < 0)
        win_rate_pct = (winning_trades / total_trades * 100.0) if total_trades > 0 else 0.0

        # Profit Factor
        gross_profit = sum(t.profit_usdt for t in completed_tranches if t.profit_usdt > 0)
        gross_loss = abs(sum(t.profit_usdt for t in completed_tranches if t.profit_usdt < 0))
        if gross_loss > 0:
            profit_factor = gross_profit / gross_loss
        else:
            profit_factor = float("inf") if gross_profit > 0 else 0.0

        # Total fees paid
        total_fees_paid = (
            sum(t.buy_fee + t.sell_fee for t in completed_tranches)
            + sum(t.buy_fee for t in active_tranches)
        )

        # Cash flow: strictly realized net profits
        cash_flow_usdt = sum(t.profit_usdt for t in completed_tranches)

        # Max days trapped
        max_days_trapped = 0.0
        for t in completed_tranches:
            if t.buy_timestamp and t.sell_timestamp:
                duration_days = (t.sell_timestamp - t.buy_timestamp) / (1000.0 * 86400.0)
                if duration_days > max_days_trapped:
                    max_days_trapped = duration_days

        if not candles_df.empty:
            last_ts = int(candles_df["timestamp"].iloc[-1])
            for t in active_tranches:
                if t.buy_timestamp:
                    duration_days = (last_ts - t.buy_timestamp) / (1000.0 * 86400.0)
                    if duration_days > max_days_trapped:
                        max_days_trapped = duration_days

        # Annualized Sharpe Ratio
        if len(equity_series) > 1:
            returns = equity_series.pct_change().dropna()
            std_dev = float(returns.std())
            if std_dev > 0:
                sharpe_ratio = float((returns.mean() / std_dev) * np.sqrt(8760))
            else:
                sharpe_ratio = 0.0
        else:
            sharpe_ratio = 0.0

        return SimulationMetrics(
            strategy_name=strategy_name,
            symbol=symbol,
            initial_capital=initial_capital,
            final_equity=final_equity,
            net_profit_usdt=net_profit_usdt,
            total_return_pct=total_return_pct,
            buy_and_hold_return_pct=buy_and_hold_return_pct,
            max_drawdown_pct=max_drawdown_pct,
            total_trades=total_trades,
            winning_trades=winning_trades,
            losing_trades=losing_trades,
            win_rate_pct=win_rate_pct,
            profit_factor=profit_factor,
            total_fees_paid=total_fees_paid,
            cash_flow_usdt=cash_flow_usdt,
            max_days_trapped=max_days_trapped,
            sharpe_ratio=sharpe_ratio,
            accumulated_satoshis=accumulated_satoshis,
            free_harvested_btc=free_harvested_btc,
        )
