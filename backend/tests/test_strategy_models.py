import unittest
from app.strategies.models import (
    MarketRegime,
    TrancheStatus,
    SignalType,
    TrancheModel,
    BotConfigModel,
    ActionSignal,
    PortfolioState,
)


class TestStrategyModels(unittest.TestCase):
    def test_tranche_model_defaults(self):
        t = TrancheModel(
            id=1,
            bot_id="btc_test_01",
            symbol="BTC/USDT",
            tranche_index=0,
            allocated_budget=250.0,
            buy_price=60000.0,
            amount=250.0 / 60000.0,
            target_sell_price=62700.0,
        )
        self.assertEqual(t.status, TrancheStatus.ACTIVE)
        self.assertEqual(t.profit_usdt, 0.0)
        self.assertEqual(t.buy_fee, 0.0)
        self.assertEqual(t.target_sell_price, 62700.0)

    def test_bot_config_defaults_and_weights(self):
        cfg = BotConfigModel(
            bot_id="btc_test_01",
            symbol="BTC/USDT",
            budget=1000.0,
        )
        self.assertEqual(cfg.take_profit_pct, 4.5)
        self.assertEqual(cfg.trailing_stop_pct, 1.4)
        self.assertEqual(cfg.trend_weight, 0.70)
        self.assertEqual(len(cfg.tranche_weights), 5)
        self.assertAlmostEqual(sum(cfg.tranche_weights), 1.0)

    def test_action_signal_creation(self):
        sig = ActionSignal(
            signal_type=SignalType.BUY_TRANCHE,
            symbol="BTC/USDT",
            tranche_index=0,
            price=61000.0,
            amount=0.005,
            allocated_usdt=305.0,
            reason="RANGE T0",
        )
        self.assertEqual(sig.signal_type, SignalType.BUY_TRANCHE)
        self.assertEqual(sig.reason, "RANGE T0")
        self.assertEqual(sig.price, 61000.0)

    def test_portfolio_state_compounding(self):
        p = PortfolioState(
            symbol="BTC/USDT",
            total_budget=1000.0,
            available_usdt=800.0,
            total_realized_profit=150.0,
            total_deposited_amount=200.0,
            total_withdrawn_amount=50.0,
        )
        effective_base = (
            p.total_budget
            + p.total_realized_profit
            + p.total_deposited_amount
            - p.total_withdrawn_amount
        )
        self.assertEqual(effective_base, 1300.0)


if __name__ == "__main__":
    unittest.main()
