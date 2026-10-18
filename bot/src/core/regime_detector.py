import pandas as pd
from src.domain.models import MarketRegime


class MarketRegimeDetector:
    """Quantitative classifier for market regime based on trend structure and volatility."""

    @staticmethod
    def detect_regime(row: pd.Series) -> MarketRegime:
        """Determines market regime for an individual candle row with precalculated indicators."""
        close = row["close"]
        ema_50 = row["ema_50"]
        ema_200 = row["ema_200"]
        rsi = row["rsi_14"]
        adx = row["adx_14"]

        # 1. Panic / Capitulation: Price below macro EMA with severe oversold conditions
        if close < ema_200 and rsi < 30.0:
            return MarketRegime.PANIC_CAPITULATION

        # 2. Strong Bull Trend: Aligned moving averages and strong directional momentum
        if close > ema_50 > ema_200 and adx >= 22.0:
            return MarketRegime.BULL_TREND

        # 3. Range / Sideways: Lack of explosive trend or consolidation
        return MarketRegime.RANGE


RegimeDetector = MarketRegimeDetector
