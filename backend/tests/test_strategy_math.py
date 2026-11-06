import unittest

try:
    import numpy as np
    import pandas as pd
    from app.strategies.indicators import TechnicalIndicators
    from app.strategies.regime import MarketRegimeDetector, MarketRegime
    PANDAS_AVAILABLE = True
except ImportError:
    PANDAS_AVAILABLE = False


class TestStrategyMath(unittest.TestCase):
    def setUp(self):
        if not PANDAS_AVAILABLE:
            self.skipTest("pandas/numpy not available in current environment")

    def test_ema_calculation(self):
        prices = pd.Series([10.0, 11.0, 12.0, 13.0, 14.0, 15.0])
        ema = TechnicalIndicators.calculate_ema(prices, period=3)
        self.assertEqual(len(ema), len(prices))
        self.assertAlmostEqual(ema.iloc[0], 10.0)
        self.assertGreater(ema.iloc[-1], ema.iloc[0])

    def test_regime_detector_panic(self):
        row = pd.Series({
            "close": 50000.0,
            "ema_50": 62000.0,
            "ema_200": 60000.0,
            "rsi_14": 22.0,
            "adx_14": 15.0,
        })
        regime = MarketRegimeDetector.detect_regime(row)
        self.assertEqual(regime, MarketRegime.PANIC_CAPITULATION)

    def test_regime_detector_bull_trend(self):
        row = pd.Series({
            "close": 70000.0,
            "ema_50": 65000.0,
            "ema_200": 60000.0,
            "rsi_14": 65.0,
            "adx_14": 28.0,
        })
        regime = MarketRegimeDetector.detect_regime(row)
        self.assertEqual(regime, MarketRegime.BULL_TREND)

    def test_regime_detector_range(self):
        row = pd.Series({
            "close": 61000.0,
            "ema_50": 61500.0,
            "ema_200": 60000.0,
            "rsi_14": 49.0,
            "adx_14": 14.0,
        })
        regime = MarketRegimeDetector.detect_regime(row)
        self.assertEqual(regime, MarketRegime.RANGE)


if __name__ == "__main__":
    unittest.main()
