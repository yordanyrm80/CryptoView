import numpy as np
import pandas as pd


class TechnicalIndicators:
    """Vectorized calculation of quantitative technical indicators without external C libraries."""

    @staticmethod
    def calculate_ema(series: pd.Series, period: int) -> pd.Series:
        """Calculates the Exponential Moving Average (EMA)."""
        return series.ewm(span=period, adjust=False).mean()

    @staticmethod
    def calculate_atr(df: pd.DataFrame, period: int = 14) -> pd.Series:
        """Calculates the Average True Range (ATR)."""
        high = df["high"]
        low = df["low"]
        close = df["close"]
        prev_close = close.shift(1)

        tr1 = high - low
        tr2 = (high - prev_close).abs()
        tr3 = (low - prev_close).abs()

        true_range = pd.concat([tr1, tr2, tr3], axis=1).max(axis=1)
        atr = true_range.ewm(alpha=1.0 / period, adjust=False).mean()
        return atr

    @staticmethod
    def calculate_rsi(series: pd.Series, period: int = 14) -> pd.Series:
        """Calculates the Relative Strength Index (Wilder's RSI)."""
        delta = series.diff()
        gain = delta.where(delta > 0, 0.0)
        loss = -delta.where(delta < 0, 0.0)

        avg_gain = gain.ewm(alpha=1.0 / period, adjust=False).mean()
        avg_loss = loss.ewm(alpha=1.0 / period, adjust=False).mean()

        rs = avg_gain / avg_loss.replace(0, np.nan)
        rsi = 100.0 - (100.0 / (1.0 + rs))
        return rsi.fillna(50.0)

    @staticmethod
    def calculate_adx(df: pd.DataFrame, period: int = 14) -> pd.Series:
        """Calculates the Average Directional Index (ADX) to measure trend strength."""
        high = df["high"]
        low = df["low"]
        close = df["close"]

        up_move = high.diff()
        down_move = -low.diff()

        plus_dm = np.where((up_move > down_move) & (up_move > 0), up_move, 0.0)
        minus_dm = np.where((down_move > up_move) & (down_move > 0), down_move, 0.0)

        atr = TechnicalIndicators.calculate_atr(df, period)

        plus_di = 100.0 * (pd.Series(plus_dm, index=df.index).ewm(alpha=1.0 / period, adjust=False).mean() / atr)
        minus_di = 100.0 * (pd.Series(minus_dm, index=df.index).ewm(alpha=1.0 / period, adjust=False).mean() / atr)

        dx = 100.0 * ((plus_di - minus_di).abs() / (plus_di + minus_di).replace(0, np.nan))
        adx = dx.ewm(alpha=1.0 / period, adjust=False).mean()
        return adx.fillna(0.0)

    @classmethod
    def apply_all(cls, df: pd.DataFrame) -> pd.DataFrame:
        """Appends all technical indicators to candle DataFrame in a single pass."""
        result = df.copy()
        result["ema_50"] = cls.calculate_ema(result["close"], 50)
        result["ema_200"] = cls.calculate_ema(result["close"], 200)
        # Macro multi-timeframe filters (1h candle equivalents)
        result["ema_4h_200"] = cls.calculate_ema(result["close"], 200 * 4)  # 800h (~33.3 days)
        result["ema_daily_200"] = cls.calculate_ema(result["close"], 200 * 24)  # 4,800h (200 days)
        result["atr_14"] = cls.calculate_atr(result, 14)
        result["rsi_14"] = cls.calculate_rsi(result["close"], 14)
        result["adx_14"] = cls.calculate_adx(result, 14)

        # Normalized volatility ratio: ATR / Close
        result["atr_pct"] = (result["atr_14"] / result["close"]) * 100.0

        # Donchian channels for momentum breakout
        result["donchian_high_48"] = result["high"].rolling(window=48).max()
        result["donchian_low_24"] = result["low"].rolling(window=24).min()
        return result
