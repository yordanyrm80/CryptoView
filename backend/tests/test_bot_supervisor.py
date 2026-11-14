import asyncio
import json
import os
import sys
import unittest
from datetime import datetime, timedelta, timezone
from typing import Any, Dict, List, Optional

import numpy as np
import pandas as pd

# Ensure backend/ is on sys.path for both `python -m unittest` and direct execution
BACKEND_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
if BACKEND_DIR not in sys.path:
    sys.path.insert(0, BACKEND_DIR)

from app.services import bot_supervisor  # noqa: E402
from app.strategies import TechnicalIndicators  # noqa: E402


def _make_candles_df(
    count: int = 300,
    base_price: float = 70000.0,
    last_close: Optional[float] = None,
    last_high: Optional[float] = None,
    last_low: Optional[float] = None,
    bull_trend: bool = False,
) -> pd.DataFrame:
    """Builds a deterministic hourly OHLCV DataFrame matching bot_supervisor expectations."""
    start_dt = datetime(2026, 11, 1, 0, 0, tzinfo=timezone.utc)
    rows = []
    for i in range(count):
        ts_ms = int((start_dt + timedelta(hours=i)).timestamp() * 1000)
        if bull_trend:
            close_px = base_price + i * 80.0
            high_px = close_px + 200.0
            low_px = close_px - 200.0
        else:
            # Oscillate above base_price early, then dip mildly on the final candle
            close_px = base_price + (500.0 if i < count - 6 else -300.0 * (i - (count - 7)))
            high_px = close_px + 150.0
            low_px = close_px - 150.0

        if i == count - 1:
            if last_close is not None:
                close_px = last_close
            if last_high is not None:
                high_px = last_high
            if last_low is not None:
                low_px = last_low

        rows.append(
            {
                "timestamp": ts_ms,
                "open": close_px,
                "high": high_px,
                "low": low_px,
                "close": close_px,
                "volume": 100.0,
            }
        )
    return pd.DataFrame(rows)


class FakePool:
    def __init__(self, conn: "FakeConn"):
        self.conn = conn

    def acquire(self):
        return _AsyncCtx(self.conn)


class _AsyncCtx:
    def __init__(self, conn):
        self.conn = conn

    async def __aenter__(self):
        return self.conn

    async def __aexit__(self, exc_type, exc, tb):
        return False


class FakeConn:
    """In-memory asyncpg-compatible connection supporting bot_supervisor SQL statements."""

    def __init__(self):
        self.bots: Dict[str, Dict[str, Any]] = {}
        self.tranches: List[Dict[str, Any]] = []
        self.orders: Dict[str, Dict[str, Any]] = {}
        self.capital_transactions: List[Dict[str, Any]] = []
        self.bot_events: List[Dict[str, Any]] = []
        self.market_candles: List[Dict[str, Any]] = []
        self.next_tranche_id = 1
        self.next_cap_id = 1
        self.next_event_id = 1

    async def fetchval(self, query: str, *args):
        q = " ".join(query.split()).lower()
        if "information_schema.tables" in q:
            return True
        if q.startswith("insert into tranches"):
            tr_id = self.next_tranche_id
            self.next_tranche_id += 1
            row = {
                "id": tr_id,
                "bot_id": args[0],
                "symbol": args[1],
                "tranche_index": args[2],
                "allocated_budget": args[3],
                "buy_price": args[4],
                "amount": args[5],
                "target_sell_price": args[6],
                "highest_price": args[4],
                "actual_sell_price": None,
                "status": "ACTIVE",
                "buy_fee": args[7],
                "sell_fee": 0.0,
                "buy_timestamp": args[8],
                "sell_timestamp": None,
                "profit_usdt": 0.0,
                "subsidized_satoshis": 0.0,
                "sell_order_id": None,
            }
            self.tranches.append(row)
            return tr_id
        raise NotImplementedError(f"Unexpected fetchval: {query}")

    async def fetchrow(self, query: str, *args):
        q = " ".join(query.split()).lower()
        if "system_settings" in q:
            return None
        if "from market_candles" in q:
            symbol = args[0]
            since_ms = int(args[1]) if len(args) > 1 else 0
            matching = [
                c for c in self.market_candles
                if c["symbol"] == symbol and c["ts_ms"] > since_ms
            ]
            if not matching:
                return {"max_high": None, "min_low": None}
            return {
                "max_high": max(c["high"] for c in matching),
                "min_low": min(c["low"] for c in matching),
            }
        raise NotImplementedError(f"Unexpected fetchrow: {query}")

    async def fetch(self, query: str, *args):
        q = " ".join(query.split()).lower()
        if "from bots where upper(status) = 'running'" in q:
            return [b for b in self.bots.values() if b["status"].upper() == "RUNNING"]
        if "from tranches where bot_id" in q:
            bot_id = args[0]
            return [t for t in self.tranches if t["bot_id"] == bot_id]
        if "from capital_transactions where bot_id" in q:
            bot_id = args[0]
            totals: Dict[str, float] = {}
            for tx in self.capital_transactions:
                if tx["bot_id"] == bot_id:
                    totals[tx["type"]] = totals.get(tx["type"], 0.0) + tx["amount"]
            return [{"type": k, "total": v} for k, v in totals.items()]
        if "from orders where bot_id = $1 and status = 'open'" in q:
            bot_id = args[0]
            rows = [o for o in self.orders.values() if o["bot_id"] == bot_id and o["status"] == "OPEN"]
            rows.sort(key=lambda r: (r["side"], r["created_at"]), reverse=False)
            rows.sort(key=lambda r: r["side"], reverse=True)
            return rows
        raise NotImplementedError(f"Unexpected fetch: {query}")

    async def execute(self, query: str, *args):
        q = " ".join(query.split()).lower()
        if q.startswith("alter table"):
            return "ALTER TABLE"
        if q.startswith("insert into orders"):
            ord_id = args[0]
            existing = self.orders.get(ord_id, {})
            self.orders[ord_id] = {
                "id": ord_id,
                "bot_id": args[1],
                "symbol": args[2],
                "side": args[3],
                "order_type": args[4],
                "price": args[5],
                "amount": args[6],
                "status": args[7],
                "fee": args[8],
                "created_at": args[9],
                "filled_at": args[10] if args[10] is not None else existing.get("filled_at"),
                "tranche_index": args[11] if args[11] is not None else existing.get("tranche_index"),
                "tranche_id": args[12] if args[12] is not None else existing.get("tranche_id"),
                "candle_timestamp": args[13] if args[13] is not None else existing.get("candle_timestamp"),
                "target_sell_price": args[14] if args[14] is not None else existing.get("target_sell_price"),
                "reason": args[15] if args[15] is not None else existing.get("reason"),
            }
            return "INSERT"
        if "update orders set status = 'closed'" in q:
            ord_id = args[4]
            self.orders[ord_id].update(
                {
                    "status": "CLOSED",
                    "price": args[0],
                    "amount": args[1],
                    "fee": args[2],
                    "filled_at": args[3],
                }
            )
            return "UPDATE 1"
        if "update orders set status = 'canceled'" in q:
            self.orders[args[0]]["status"] = "CANCELED"
            return "UPDATE 1"
        if "update orders set tranche_id = $1 where id = $2" in q:
            self.orders[args[1]]["tranche_id"] = args[0]
            return "UPDATE 1"
        if "update tranches set highest_price" in q:
            for t in self.tranches:
                if t["id"] == args[1]:
                    t["highest_price"] = args[0]
            return "UPDATE 1"
        if "update tranches set sell_order_id" in q:
            if "sell_order_id = null" in q:
                for t in self.tranches:
                    if t["id"] == args[0]:
                        t["sell_order_id"] = None
            else:
                for t in self.tranches:
                    if t["id"] == args[1]:
                        t["sell_order_id"] = args[0]
            return "UPDATE 1"
        if "update tranches set status = 'closed'" in q:
            for t in self.tranches:
                if t["id"] == args[4]:
                    t.update(
                        {
                            "status": "CLOSED",
                            "actual_sell_price": args[0],
                            "sell_fee": args[1],
                            "sell_timestamp": args[2],
                            "profit_usdt": args[3],
                            "sell_order_id": None,
                        }
                    )
            return "UPDATE 1"
        if "update tranches set target_sell_price" in q:
            for t in self.tranches:
                if t["id"] == args[2]:
                    t["target_sell_price"] = args[0]
                    t["subsidized_satoshis"] = args[1]
            return "UPDATE 1"
        if "update bots set config_json" in q:
            self.bots[args[2]]["config_json"] = args[0]
            self.bots[args[2]]["updated_at"] = args[1]
            return "UPDATE 1"
        if q.startswith("insert into bot_events"):
            import re

            m = re.search(r"values\s*\(\s*\$1\s*,\s*'([^']+)'\s*,\s*\$2\s*,\s*\$3\s*\)", q)
            ev_type = m.group(1).upper() if m else "EVENT"
            self.bot_events.append(
                {
                    "id": self.next_event_id,
                    "bot_id": args[0],
                    "event_type": ev_type,
                    "details": args[1],
                    "timestamp": args[2],
                }
            )
            self.next_event_id += 1
            return "INSERT"
        if q.startswith("insert into capital_transactions"):
            self.capital_transactions.append(
                {
                    "id": self.next_cap_id,
                    "bot_id": args[0],
                    "type": args[1],
                    "amount": args[2],
                    "available_after": args[3],
                    "timestamp": args[4],
                    "reason": args[5],
                }
            )
            self.next_cap_id += 1
            return "INSERT"
        raise NotImplementedError(f"Unexpected execute: {query}")


class FakeExchange:
    """Controllable mock KuCoin CCXT async client."""

    def __init__(self, quote_free: float = 2000.0, quote_total: float = 2000.0, base_free: float = 0.0):
        self.quote_free = quote_free
        self.quote_total = quote_total
        self.base_free = base_free
        self.orders: Dict[str, Dict[str, Any]] = {}
        self.created_calls: List[Dict[str, Any]] = []
        self.canceled_ids: List[str] = []
        self.closed = False
        self._seq = 1

    def amount_to_precision(self, symbol: str, amount: float) -> str:
        return f"{float(amount):.8f}"

    def price_to_precision(self, symbol: str, price: float) -> str:
        return f"{float(price):.1f}"

    async def fetch_balance(self) -> Dict[str, Any]:
        return {
            "USDT": {"free": self.quote_free, "total": self.quote_total},
            "BTC": {"free": self.base_free, "total": self.base_free},
        }

    async def create_order(
        self, symbol: str, type: str, side: str, amount: float, price: Optional[float] = None
    ) -> Dict[str, Any]:
        ord_id = f"kucoin_ord_{self._seq}"
        self._seq += 1
        self.created_calls.append(
            {"id": ord_id, "symbol": symbol, "type": type, "side": side, "amount": amount, "price": price}
        )
        if type == "market":
            fill_px = 75000.0
            cost = amount * fill_px
            rec = {
                "id": ord_id,
                "symbol": symbol,
                "type": type,
                "side": side,
                "status": "closed",
                "price": fill_px,
                "average": fill_px,
                "amount": amount,
                "filled": amount,
                "remaining": 0.0,
                "cost": cost,
                "fee": {"cost": cost * 0.001, "currency": "USDT"},
                "timestamp": 1700000000000,
            }
        else:
            rec = {
                "id": ord_id,
                "symbol": symbol,
                "type": type,
                "side": side,
                "status": "open",
                "price": price,
                "average": None,
                "amount": amount,
                "filled": 0.0,
                "remaining": amount,
                "cost": 0.0,
                "fee": None,
                "timestamp": 1700000000000,
            }
            if side == "buy":
                locked = (price or 0.0) * amount * 1.001
                self.quote_free = max(0.0, self.quote_free - locked)
            elif side == "sell":
                self.base_free = max(0.0, self.base_free - amount)
        self.orders[ord_id] = rec
        return dict(rec)

    async def fetch_order(self, order_id: str, symbol: str) -> Dict[str, Any]:
        return dict(self.orders[order_id])

    async def cancel_order(self, order_id: str, symbol: str) -> Dict[str, Any]:
        self.canceled_ids.append(order_id)
        ord_rec = self.orders[order_id]
        if ord_rec["status"] == "open":
            ord_rec["status"] = "canceled"
            if ord_rec["side"] == "buy":
                self.quote_free += (ord_rec["price"] or 0.0) * ord_rec["remaining"] * 1.001
            elif ord_rec["side"] == "sell":
                self.base_free += ord_rec["remaining"]
        return dict(ord_rec)

    async def close(self) -> None:
        self.closed = True


class TestBotSupervisorLimitExecution(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self._orig_load = bot_supervisor._load_hourly_candles_df
        self._orig_discord = bot_supervisor.send_discord_bot_embed

        async def _noop_discord(*args, **kwargs):
            return True

        bot_supervisor.send_discord_bot_embed = _noop_discord

    async def asyncTearDown(self):
        bot_supervisor._load_hourly_candles_df = self._orig_load
        bot_supervisor.send_discord_bot_embed = self._orig_discord

    def _patch_candles(self, df: pd.DataFrame):
        async def _loader(conn, symbol):
            return df.copy()

        bot_supervisor._load_hourly_candles_df = _loader

    def test_extract_fill_metrics_handles_fees_list_and_base_currency(self):
        metrics = bot_supervisor._extract_fill_metrics(
            {
                "status": "closed",
                "filled": 0.00668069,
                "cost": 500.155860576,
                "average": None,
                "price": 74842.5,
                "fees": [
                    {"cost": 0.30, "currency": "USDT"},
                    {"cost": 0.200155860576, "currency": "USDT"},
                ],
                "timestamp": 1700001234000,
            },
            "BTC/USDT",
        )
        self.assertEqual(metrics["status"], "closed")
        self.assertAlmostEqual(metrics["avg_price"], 500.155860576 / 0.00668069, places=4)
        self.assertAlmostEqual(metrics["fee_usdt"], 0.500155860576, places=9)

        # Base currency fee conversion
        base_fee = bot_supervisor._extract_fill_metrics(
            {
                "status": "closed",
                "filled": 0.01,
                "cost": 700.0,
                "average": 70000.0,
                "fee": {"cost": 0.00001, "currency": "BTC"},
            },
            "BTC/USDT",
        )
        self.assertAlmostEqual(base_fee["fee_usdt"], 0.70, places=6)

    async def test_live_buy_limit_resting_then_fill_places_sell_limit(self):
        # Force PANIC_CAPITULATION RSI < 28 so T0 BUY signal fires cleanly
        df = _make_candles_df(count=300, base_price=80000.0)
        # Crash final candles to pull close below EMA200 and RSI < 28
        for idx in range(285, 300):
            drop = (idx - 284) * 1400.0
            df.loc[idx, "close"] = 80000.0 - drop
            df.loc[idx, "open"] = df.loc[idx, "close"] + 100.0
            df.loc[idx, "high"] = df.loc[idx, "close"] + 200.0
            df.loc[idx, "low"] = df.loc[idx, "close"] - 200.0

        self._patch_candles(df)
        conn = FakeConn()
        conn.bots["bot_live"] = {
            "bot_id": "bot_live",
            "symbol": "BTC/USDT",
            "budget": 2000.0,
            "dry_run": False,
            "status": "RUNNING",
            "config_json": json.dumps({"panic_rsi_threshold": 28.0, "take_profit_pct": 4.5}),
            "created_at": 1,
        }
        ex = FakeExchange(quote_free=2000.0, quote_total=2000.0, base_free=0.0)

        async def _factory(c, cfg):
            ex.closed = False
            return ex

        # Cycle 1: Should place a BUY LIMIT (NOT market!) and leave tranche unactivated while OPEN
        count = await bot_supervisor.evaluate_running_bots(FakePool(conn), exchange_factory=_factory)
        self.assertEqual(count, 1)
        self.assertTrue(ex.closed)
        self.assertEqual(len(ex.created_calls), 1)
        self.assertEqual(ex.created_calls[0]["type"], "limit")
        self.assertEqual(ex.created_calls[0]["side"], "buy")
        buy_ord_id = ex.created_calls[0]["id"]
        self.assertEqual(conn.orders[buy_ord_id]["status"], "OPEN")
        self.assertEqual(len(conn.tranches), 0)

        # Cycle 2 (same closed candle, order still open): Must NOT place duplicate BUY LIMIT
        await bot_supervisor.evaluate_running_bots(FakePool(conn), exchange_factory=_factory)
        self.assertEqual(len(ex.created_calls), 1)

        # Simulate Maker fill on KuCoin at slightly improved price
        ord_rec = ex.orders[buy_ord_id]
        fill_price = float(ord_rec["price"]) - 10.0
        fill_amt = float(ord_rec["amount"])
        fill_cost = fill_price * fill_amt
        fill_fee = fill_cost * 0.001
        ord_rec.update(
            {
                "status": "closed",
                "average": fill_price,
                "filled": fill_amt,
                "remaining": 0.0,
                "cost": fill_cost,
                "fee": {"cost": fill_fee, "currency": "USDT"},
                "timestamp": int(df.iloc[-1]["timestamp"]) + 60000,
            }
        )
        ex.base_free += fill_amt
        ex.quote_total -= (fill_cost + fill_fee)
        # Free excess locked fee delta
        ex.quote_free = ex.quote_total

        # Cycle 3: BUY LIMIT fill detected -> Tranche activated with real fill metrics + SELL LIMIT placed
        await bot_supervisor.evaluate_running_bots(FakePool(conn), exchange_factory=_factory)
        self.assertEqual(conn.orders[buy_ord_id]["status"], "CLOSED")
        self.assertEqual(len(conn.tranches), 1)
        tr = conn.tranches[0]
        self.assertEqual(tr["status"], "ACTIVE")
        self.assertAlmostEqual(tr["buy_price"], fill_price, places=2)
        self.assertAlmostEqual(tr["allocated_budget"], fill_cost, places=4)
        self.assertAlmostEqual(tr["buy_fee"], fill_fee, places=6)
        # PANIC regime uses 1.07 (+7%) target multiplier!
        self.assertAlmostEqual(tr["target_sell_price"], fill_price * 1.07, places=2)
        self.assertIsNotNone(tr["sell_order_id"])

        sell_call = ex.created_calls[-1]
        self.assertEqual(sell_call["type"], "limit")
        self.assertEqual(sell_call["side"], "sell")
        self.assertEqual(conn.orders[sell_call["id"]]["status"], "OPEN")

    async def test_variant_a_buy_limit_expires_on_new_candle_and_activates_partial_fill(self):
        df1 = _make_candles_df(count=300, base_price=70000.0)
        self._patch_candles(df1)
        conn = FakeConn()
        conn.bots["bot_exp"] = {
            "bot_id": "bot_exp",
            "symbol": "BTC/USDT",
            "budget": 2000.0,
            "dry_run": False,
            "status": "RUNNING",
            "config_json": json.dumps({}),
            "created_at": 1,
        }
        old_candle_ts = int(df1.iloc[-1]["timestamp"])
        # Pre-seed an OPEN BUY LIMIT order from old_candle_ts
        ex = FakeExchange(quote_free=1400.0, quote_total=2000.0, base_free=0.0)
        ex.orders["old_buy_1"] = {
            "id": "old_buy_1",
            "symbol": "BTC/USDT",
            "type": "limit",
            "side": "buy",
            "status": "open",
            "price": 70000.0,
            "average": None,
            "amount": 0.008,
            "filled": 0.0,
            "remaining": 0.008,
            "cost": 0.0,
            "fee": None,
            "timestamp": old_candle_ts,
        }
        conn.orders["old_buy_1"] = {
            "id": "old_buy_1",
            "bot_id": "bot_exp",
            "symbol": "BTC/USDT",
            "side": "BUY",
            "order_type": "LIMIT",
            "price": 70000.0,
            "amount": 0.008,
            "status": "OPEN",
            "fee": 0.0,
            "created_at": old_candle_ts + 1000,
            "filled_at": None,
            "tranche_index": 0,
            "tranche_id": None,
            "candle_timestamp": old_candle_ts,
            "target_sell_price": 73150.0,
            "reason": "RANGE T0",
        }

        async def _factory(c, cfg):
            return ex

        # Advance 1 hourly candle -> old_buy_1 must expire & cancel cleanly
        df2 = _make_candles_df(count=301, base_price=70000.0)
        self._patch_candles(df2)
        await bot_supervisor.evaluate_running_bots(FakePool(conn), exchange_factory=_factory)
        self.assertIn("old_buy_1", ex.canceled_ids)
        self.assertEqual(conn.orders["old_buy_1"]["status"], "CANCELED")
        self.assertEqual(len(conn.tranches), 0)

        # Subcase B: Partial fill >= $10 when expired -> activates tranche + places resting SELL LIMIT
        ex.orders["old_buy_2"] = {
            "id": "old_buy_2",
            "symbol": "BTC/USDT",
            "type": "limit",
            "side": "buy",
            "status": "open",
            "price": 70000.0,
            "average": 69990.0,
            "amount": 0.008,
            "filled": 0.002,
            "remaining": 0.006,
            "cost": 139.98,
            "fee": {"cost": 0.13998, "currency": "USDT"},
            "timestamp": old_candle_ts + 5000,
        }
        conn.orders["old_buy_2"] = {
            "id": "old_buy_2",
            "bot_id": "bot_exp",
            "symbol": "BTC/USDT",
            "side": "BUY",
            "order_type": "LIMIT",
            "price": 70000.0,
            "amount": 0.008,
            "status": "OPEN",
            "fee": 0.0,
            "created_at": old_candle_ts + 1000,
            "filled_at": None,
            "tranche_index": 0,
            "tranche_id": None,
            "candle_timestamp": old_candle_ts,
            "target_sell_price": 73150.0,
            "reason": "RANGE T0",
        }
        ex.base_free = 0.002
        ex.quote_total = 2000.0 - 139.98 - 0.13998
        ex.quote_free = ex.quote_total

        await bot_supervisor.evaluate_running_bots(FakePool(conn), exchange_factory=_factory)
        self.assertIn("old_buy_2", ex.canceled_ids)
        self.assertEqual(conn.orders["old_buy_2"]["status"], "CLOSED")
        self.assertEqual(len(conn.tranches), 1)
        self.assertAlmostEqual(conn.tranches[0]["amount"], 0.002, places=6)
        self.assertIsNotNone(conn.tranches[0]["sell_order_id"])

    async def test_existing_tranches_place_resting_sell_limits_and_cascade_replaces(self):
        df = _make_candles_df(count=300, base_price=71000.0)
        self._patch_candles(df)
        latest_ts = int(df.iloc[-1]["timestamp"])
        conn = FakeConn()
        conn.bots["apex_live"] = {
            "bot_id": "apex_live",
            "symbol": "BTC/USDT",
            "budget": 2000.0,
            "dry_run": False,
            "status": "RUNNING",
            "config_json": json.dumps({}),
            "created_at": 1,
        }
        # Seed T0 (hung higher buy) & T1 (lower buy) with no resting sell_order_id yet
        conn.tranches.extend(
            [
                {
                    "id": 7,
                    "bot_id": "apex_live",
                    "symbol": "BTC/USDT",
                    "tranche_index": 0,
                    "allocated_budget": 600.22,
                    "buy_price": 75717.8,
                    "amount": 0.00792709,
                    "target_sell_price": 79125.1,
                    "highest_price": 75717.8,
                    "actual_sell_price": None,
                    "status": "ACTIVE",
                    "buy_fee": 0.60,
                    "sell_fee": 0.0,
                    "buy_timestamp": latest_ts - 100000,
                    "sell_timestamp": None,
                    "profit_usdt": 0.0,
                    "subsidized_satoshis": 0.0,
                    "sell_order_id": None,
                },
                {
                    "id": 8,
                    "bot_id": "apex_live",
                    "symbol": "BTC/USDT",
                    "tranche_index": 1,
                    "allocated_budget": 300.12,
                    "buy_price": 69133.6,
                    "amount": 0.00434111,
                    "target_sell_price": 72244.6,
                    "highest_price": 71000.0,
                    "actual_sell_price": None,
                    "status": "ACTIVE",
                    "buy_fee": 0.30,
                    "sell_fee": 0.0,
                    "buy_timestamp": latest_ts - 50000,
                    "sell_timestamp": None,
                    "profit_usdt": 0.0,
                    "subsidized_satoshis": 0.0,
                    "sell_order_id": None,
                },
            ]
        )
        ex = FakeExchange(
            quote_free=1098.76,
            quote_total=1098.76,
            base_free=0.00792709 + 0.00434111,
        )

        async def _factory(c, cfg):
            return ex

        # Cycle 1: Must place 2 resting SELL LIMIT orders (one for T0, one for T1)
        await bot_supervisor.evaluate_running_bots(FakePool(conn), exchange_factory=_factory)
        sell_calls = [c for c in ex.created_calls if c["side"] == "sell" and c["type"] == "limit"]
        self.assertEqual(len(sell_calls), 2)
        t0_sell_id = conn.tranches[0]["sell_order_id"]
        t1_sell_id = conn.tranches[1]["sell_order_id"]
        self.assertIsNotNone(t0_sell_id)
        self.assertIsNotNone(t1_sell_id)

        # Simulate T1 SELL LIMIT fill -> realizes profit -> cascades 35% discount to T0 -> replaces t0_sell_id
        t1_sell_amt = 0.00434111
        t1_fill_px = 72244.6
        t1_rev = t1_sell_amt * t1_fill_px
        t1_fee = t1_rev * 0.001
        ex.orders[t1_sell_id].update(
            {
                "status": "closed",
                "average": t1_fill_px,
                "filled": t1_sell_amt,
                "remaining": 0.0,
                "cost": t1_rev,
                "fee": {"cost": t1_fee, "currency": "USDT"},
                "timestamp": latest_ts + 1000,
            }
        )
        ex.quote_free += (t1_rev - t1_fee)
        ex.quote_total += (t1_rev - t1_fee)

        await bot_supervisor.evaluate_running_bots(FakePool(conn), exchange_factory=_factory)
        self.assertEqual(conn.tranches[1]["status"], "CLOSED")
        self.assertGreater(conn.tranches[1]["profit_usdt"], 0.0)
        # Old T0 SELL LIMIT was canceled and replaced with lowered target_sell_price
        self.assertIn(t0_sell_id, ex.canceled_ids)
        self.assertEqual(conn.orders[t0_sell_id]["status"], "CANCELED")
        self.assertNotEqual(conn.tranches[0]["sell_order_id"], t0_sell_id)
        self.assertLess(conn.tranches[0]["target_sell_price"], 79125.1)
        self.assertGreater(conn.tranches[0]["subsidized_satoshis"], 0.0)

    async def test_trailing_stop_cancels_sell_limit_before_market_sell_and_no_prebuy_leak(self):
        # Construct steady BULL_TREND where latest completed candle had a HUGE pre-buy low wick
        df = _make_candles_df(
            count=300,
            base_price=60000.0,
            bull_trend=True,
            last_high=95000.0,
            last_low=65000.0,
        )
        self._patch_candles(df)
        latest_ts = int(df.iloc[-1]["timestamp"])
        buy_ts = latest_ts + 120_000  # Bought AFTER latest closed 1h candle!

        conn = FakeConn()
        conn.bots["bull_bot"] = {
            "bot_id": "bull_bot",
            "symbol": "BTC/USDT",
            "budget": 2000.0,
            "dry_run": False,
            "status": "RUNNING",
            "config_json": json.dumps({"trend_highest_price": 86000.0, "trailing_stop_pct": 1.4}),
            "created_at": 1,
        }
        conn.tranches.append(
            {
                "id": 1,
                "bot_id": "bull_bot",
                "symbol": "BTC/USDT",
                "tranche_index": 0,
                "allocated_budget": 1400.0,
                "buy_price": 82000.0,
                "amount": 0.01707317,
                "target_sell_price": 164000.0,
                "highest_price": 86000.0,
                "actual_sell_price": None,
                "status": "ACTIVE",
                "buy_fee": 1.4,
                "sell_fee": 0.0,
                "buy_timestamp": buy_ts,
                "sell_timestamp": None,
                "profit_usdt": 0.0,
                "subsidized_satoshis": 0.0,
                "sell_order_id": None,
            }
        )
        # Post-buy market_candles stay safely at $86,000 -> no trailing stop leak from pre-buy 65k wick!
        conn.market_candles.append(
            {"symbol": "BTC/USDT", "ts_ms": buy_ts + 60_000, "high": 86000.0, "low": 85900.0, "close": 86000.0}
        )

        ex = FakeExchange(quote_free=598.6, quote_total=598.6, base_free=0.01707317)

        async def _factory(c, cfg):
            return ex

        await bot_supervisor.evaluate_running_bots(FakePool(conn), exchange_factory=_factory)
        self.assertEqual(conn.tranches[0]["status"], "ACTIVE")
        sell_limit_id = conn.tranches[0]["sell_order_id"]
        self.assertIsNotNone(sell_limit_id)

        # Now add a real post-buy drop below 86000 * (1 - 0.014) = 84796
        conn.market_candles.append(
            {"symbol": "BTC/USDT", "ts_ms": buy_ts + 120_000, "high": 85000.0, "low": 84500.0, "close": 84600.0}
        )
        await bot_supervisor.evaluate_running_bots(FakePool(conn), exchange_factory=_factory)
        self.assertIn(sell_limit_id, ex.canceled_ids)
        self.assertEqual(conn.orders[sell_limit_id]["status"], "CANCELED")
        market_sells = [c for c in ex.created_calls if c["type"] == "market" and c["side"] == "sell"]
        self.assertEqual(len(market_sells), 1)
        self.assertEqual(conn.tranches[0]["status"], "CLOSED")
        self.assertEqual(conn.orders[market_sells[0]["id"]]["order_type"], "STOP_MARKET")

    async def test_live_balance_reconciliation_logs_external_deposit(self):
        df = _make_candles_df(count=300, base_price=70000.0)
        self._patch_candles(df)
        conn = FakeConn()
        conn.bots["sync_bot"] = {
            "bot_id": "sync_bot",
            "symbol": "BTC/USDT",
            "budget": 2000.0,
            "dry_run": False,
            "status": "RUNNING",
            "config_json": json.dumps({}),
            "created_at": 1,
        }
        # Simulate external +500 USDT deposit on KuCoin subaccount
        ex = FakeExchange(quote_free=2500.0, quote_total=2500.0, base_free=0.0)

        async def _factory(c, cfg):
            return ex

        await bot_supervisor.evaluate_running_bots(FakePool(conn), exchange_factory=_factory)
        self.assertEqual(len(conn.capital_transactions), 1)
        self.assertEqual(conn.capital_transactions[0]["type"], "DEPOSIT")
        self.assertAlmostEqual(conn.capital_transactions[0]["amount"], 500.0, places=2)


if __name__ == "__main__":
    unittest.main()
