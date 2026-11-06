import pandas as pd
from app.strategies.models import MarketRegime


class MarketRegimeDetector:
    """Quantitative classifier for market regime."""

    @staticmethod
    def detect_regime(row: pd.Series) -> MarketRegime:
        close = row["close"]
        ema_50 = row["ema_50"]
        ema_200 = row["ema_200"]
        rsi = row["rsi_14"]
        adx = row["adx_14"]

        if close < ema_200 and rsi < 30.0:
            return MarketRegime.PANIC_CAPITULATION

        if close > ema_50 > ema_200 and adx >= 22.0:
            return MarketRegime.BULL_TREND

        return MarketRegime.RANGE
