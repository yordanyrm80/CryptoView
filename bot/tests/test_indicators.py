import numpy as np
import pandas as pd
import pytest
from src.indicators.technical import TechnicalIndicators


@pytest.fixture
def sample_candles_df():
    # Generar 60 velas sintéticas con una tendencia alcista clara
    np.random.seed(42)
    dates = pd.date_range("2024-01-01", periods=60, freq="h", tz="UTC")
    base_price = 50000.0 + np.cumsum(np.random.normal(50, 100, 60))
    
    df = pd.DataFrame(
        {
            "timestamp": [int(d.timestamp() * 1000) for d in dates],
            "open": base_price - 20,
            "high": base_price + 80,
            "low": base_price - 70,
            "close": base_price,
            "volume": np.random.uniform(10, 50, 60),
        },
        index=dates,
    )
    return df


def test_technical_indicators_calculation(sample_candles_df):
    df_result = TechnicalIndicators.apply_all(sample_candles_df)

    assert "ema_50" in df_result.columns
    assert "ema_200" in df_result.columns
    assert "atr_14" in df_result.columns
    assert "rsi_14" in df_result.columns
    assert "adx_14" in df_result.columns
    assert "atr_pct" in df_result.columns

    # Verificar que los valores de RSI están en el rango válido [0, 100]
    assert df_result["rsi_14"].min() >= 0.0
    assert df_result["rsi_14"].max() <= 100.0

    # ATR debe ser estrictamente positivo
    assert (df_result["atr_14"] > 0).all()
