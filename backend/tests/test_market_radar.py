import asyncio
import os
import sys
import unittest
from datetime import datetime, timedelta, timezone

# Ensure backend/ is on sys.path for both `python -m unittest` and direct execution
BACKEND_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
if BACKEND_DIR not in sys.path:
    sys.path.insert(0, BACKEND_DIR)

from app.services.market_radar import MarketCycleRadarService  # noqa: E402

try:
    from app.routers import bots as bots_router  # noqa: E402
    BOTS_ROUTER_AVAILABLE = True
except ImportError:
    bots_router = None
    BOTS_ROUTER_AVAILABLE = False


class _FakeConn:
    def __init__(self, ath: float, rows: list):
        self._ath = ath
        self._rows = rows

    async def fetchrow(self, query: str, *args):
        return {"ath": self._ath}

    async def fetch(self, query: str, *args):
        return self._rows


class _AcquireCtx:
    def __init__(self, conn: _FakeConn):
        self._conn = conn

    async def __aenter__(self):
        return self._conn

    async def __aexit__(self, exc_type, exc, tb):
        return False


class _FakePool:
    def __init__(self, ath: float, rows: list):
        self._conn = _FakeConn(ath, rows)

    def acquire(self):
        return _AcquireCtx(self._conn)


def _build_hourly_rows(
    count: int,
    start_price: float,
    end_price: float,
) -> list:
    """Returns descending rows matching `SELECT ... ORDER BY time DESC`."""
    now = datetime(2026, 11, 14, 12, 0, tzinfo=timezone.utc)
    rows = []
    for idx in range(count):
        frac = idx / max(count - 1, 1)
        px = start_price + (end_price - start_price) * frac
        rows.append(
            {
                "time": now - timedelta(hours=(count - 1 - idx)),
                "open": px,
                "high": px * 1.005,
                "low": px * 0.995,
                "close": px,
                "volume": 100.0,
            }
        )
    rows.reverse()
    return rows


class MarketRadarTests(unittest.TestCase):
    def test_profiles_are_customized_per_asset_with_generic_fallback(self):
        btc = MarketCycleRadarService.get_profile("BTC/USDT")
        eth = MarketCycleRadarService.get_profile("ETH/USDT")
        kcs = MarketCycleRadarService.get_profile("KCS/USDT")
        generic = MarketCycleRadarService.get_profile("SOL-USDT")

        self.assertEqual(btc["capitulation_drawdown_pct"], -55.0)
        self.assertTrue(btc["use_btc_halving_window"])

        # Preserves exact validated ETH thresholds from research
        self.assertEqual(eth["capitulation_drawdown_pct"], -50.0)
        self.assertEqual(eth["capitulation_rsi"], 35.0)
        self.assertEqual(eth["capitulation_avg_return_1y"], 136.0)
        self.assertEqual(eth["golden_avg_return_1y"], 182.9)
        self.assertEqual(eth["overheated_dist_ema200_pct"], 40.0)
        self.assertEqual(eth["overheated_rsi"], 70.0)

        self.assertEqual(kcs["label"], "Generic Crypto Profile")
        self.assertEqual(kcs["base_asset"], "KCS")
        self.assertFalse(kcs["use_btc_halving_window"])

        self.assertEqual(generic["label"], "Generic Crypto Profile")
        self.assertEqual(generic["base_asset"], "SOL")

    def test_price_decimals_scales_cleanly_for_altcoins(self):
        self.assertEqual(MarketCycleRadarService._price_decimals(90000.0), 2)
        self.assertEqual(MarketCycleRadarService._price_decimals(8.5), 4)
        self.assertEqual(MarketCycleRadarService._price_decimals(0.045), 6)

    def test_eth_capitulation_signal_and_generic_coin_analysis(self):
        # Sharp drop from 4000 ATH to 1800 (-55% drawdown, RSI deeply oversold)
        rows = _build_hourly_rows(count=600, start_price=4000.0, end_price=1800.0)
        pool = _FakePool(ath=4200.0, rows=rows)

        eth_res = asyncio.run(MarketCycleRadarService.analyze_market_cycle(pool, "ETH-USDT"))
        self.assertEqual(eth_res["symbol"], "ETH/USDT")
        self.assertEqual(eth_res["entry_radar"]["status"], "PANIC_CAPITULATION")
        self.assertEqual(eth_res["entry_radar"]["historical_avg_return_1y_pct"], 136.0)
        self.assertIn("pi_cycle_metrics", eth_res)

        alt_rows = _build_hourly_rows(count=300, start_price=5.0, end_price=5.2)
        alt_pool = _FakePool(ath=8.0, rows=alt_rows)
        alt_res = asyncio.run(MarketCycleRadarService.analyze_market_cycle(alt_pool, "NEW/USDT"))
        self.assertEqual(alt_res["symbol"], "NEW/USDT")
        self.assertEqual(alt_res["profile_label"], "Generic Crypto Profile")

    @unittest.skipUnless(
        BOTS_ROUTER_AVAILABLE,
        "FastAPI/CCXT dependencies not installed in local host environment",
    )
    def test_official_presets_include_eth_ultra_and_btc_flagship(self):
        ids = {p["id"]: p for p in bots_router.OFFICIAL_STRATEGY_PRESETS}
        self.assertIn("recommended_btc_quantum_evolution", ids)
        self.assertIn("recommended_eth_ultra", ids)

        eth_params = ids["recommended_eth_ultra"]["params"]
        self.assertEqual(eth_params["take_profit_pct"], 4.2)
        self.assertEqual(eth_params["trailing_stop_pct"], 1.4)
        self.assertEqual(eth_params["trend_weight"], 0.85)
        self.assertEqual(eth_params["floor_tranche_weights"], [0.50, 0.35, 0.25])


if __name__ == "__main__":
    unittest.main()
