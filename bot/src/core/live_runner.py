import asyncio
import logging
import os
import time
from typing import Any, Dict, List, Optional
import pandas as pd
from src.core.event_bus import DomainEvent, EventBus
from src.domain.models import BotInstance, Order, OrderSide, OrderStatus, OrderType, Tranche, TrancheStatus
from src.indicators.technical import TechnicalIndicators
from src.storage.candle_repository import CandleRepository
from src.storage.capital_repository import CapitalRepository
from src.storage.database import DatabaseManager
from src.storage.order_repository import OrderRepository
from src.storage.tranche_repository import TrancheRepository
from src.strategies.base import BaseStrategy, PortfolioState, SignalType
from src.strategies.btc_quantum_compound_regime import BtcQuantumCompoundRegimeStrategy
from src.strategies.btc_quantum_evolution_regime import BtcQuantumEvolutionRegimeStrategy

logger = logging.getLogger("criptobot.live_runner")


class LiveRunner:
    """Institutional Order Management System (OMS) and strategy runner.

    Operates strictly via resting Limit Orders (Maker execution).
    Decoupled from market ingestion, telemetry, and external notifications via EventBus.
    """

    def __init__(
        self,
        bots: Optional[Dict[str, BotInstance]] = None,
        db_manager: Optional[DatabaseManager] = None,
        event_bus: Optional[EventBus] = None,
        interval_seconds: float = 10.0,
        fee_rate: float = 0.001,
        recycle_fraction: float = 0.35,
        max_subsidized_discount_pct: float = 0.12,
        kucoin_client: Optional[Any] = None,
        bot_service: Optional[Any] = None,
    ):
        self.db_manager = db_manager or DatabaseManager()
        self.event_bus = event_bus or EventBus.get_instance()
        self.candle_repo = CandleRepository(self.db_manager)
        self.tranche_repo = TrancheRepository(self.db_manager)
        self.order_repo = OrderRepository(self.db_manager)
        self.capital_repo = CapitalRepository(self.db_manager)

        self._bots_dict = bots
        self._bot_service = bot_service

        self.interval_seconds = interval_seconds
        self.fee_rate = fee_rate
        self.recycle_fraction = recycle_fraction
        self.max_subsidized_discount_pct = max_subsidized_discount_pct

        self._default_client: Optional[Any] = kucoin_client
        if self._default_client is None:
            api_key = os.getenv("KUCOIN_API_KEY")
            secret = os.getenv("KUCOIN_API_SECRET")
            passphrase = os.getenv("KUCOIN_API_PASSPHRASE")
            if api_key and secret and passphrase:
                from src.exchange.client import KuCoinClient
                self._default_client = KuCoinClient(api_key, secret, passphrase)

        # Isolated subaccount client pool: {bot_id: KuCoinClient}
        self._subaccount_clients: Dict[str, Any] = {}

        self._task: Optional[asyncio.Task] = None
        self._running: bool = False
        self._strategies: Dict[str, BaseStrategy] = {}
        # Tracking resting order IDs mapped to tranche index: {bot_id: {tranche_index: order_id}}
        self._pending_buy_orders: Dict[str, Dict[int, str]] = {}
        self._pending_sell_orders: Dict[str, Dict[int, str]] = {}

    @property
    def kucoin_client(self) -> Optional[Any]:
        return self._default_client

    @kucoin_client.setter
    def kucoin_client(self, client: Optional[Any]) -> None:
        self._default_client = client

    def set_exchange_client(self, bot_id: str, client: Any) -> None:
        """Explicitly registers an isolated exchange client for a specific bot (useful for tests or injection)."""
        self._subaccount_clients[bot_id] = client

    def get_exchange_client(self, bot: BotInstance) -> Optional[Any]:
        """
        Returns the isolated KuCoin client for the bot's subaccount.

        Strict Zero-Trust Rule:
        - If bot.dry_run is True: returns None (simulated execution, zero exchange calls).
        - If bot.dry_run is False: the bot MUST have dedicated subaccount credentials
          (api_key, api_secret, api_passphrase).
          FALLBACK TO DEFAULT/GLOBAL/MASTER ACCOUNTS IS STRICTLY PROHIBITED.
        """
        if bot.dry_run:
            return None

        bot_id = bot.config.bot_id
        if bot_id in self._subaccount_clients:
            return self._subaccount_clients[bot_id]

        if (
            bot.config.api_key
            and bot.config.api_key.strip()
            and bot.config.api_secret
            and bot.config.api_secret.strip()
            and bot.config.api_passphrase
            and bot.config.api_passphrase.strip()
        ):
            from src.exchange.client import KuCoinClient
            client = KuCoinClient(
                bot.config.api_key.strip(),
                bot.config.api_secret.strip(),
                bot.config.api_passphrase.strip(),
            )
            self._subaccount_clients[bot_id] = client
            logger.info(
                f"Initialized isolated subaccount KuCoin client for bot '{bot_id}' "
                f"({bot.config.subaccount_name or 'subaccount'})"
            )
            return client

        raise ValueError(
            f"CRITICAL ZERO-TRUST SECURITY VIOLATION: Bot '{bot_id}' is configured for LIVE trading "
            f"(dry_run=False) but lacks dedicated subaccount credentials (api_key, api_secret, api_passphrase). "
            f"Fallback to default or master accounts is strictly prohibited."
        )

    @property
    def bots(self) -> Dict[str, BotInstance]:
        if self._bots_dict is not None:
            return self._bots_dict
        if self._bot_service is not None:
            return self._bot_service.bots
        from src.api.services.bot_service import BotService
        return BotService.get_instance().bots

    def _get_strategy(self, bot_id: str, strategy_name: str, config) -> BaseStrategy:
        if bot_id not in self._strategies:
            if strategy_name == "BtcQuantumEvolutionRegimeStrategy":
                self._strategies[bot_id] = BtcQuantumEvolutionRegimeStrategy(config=config)
            else:
                self._strategies[bot_id] = BtcQuantumCompoundRegimeStrategy(config=config)
        return self._strategies[bot_id]

    async def run_cycle(self):
        """Executes a single evaluation and order reconciliation cycle across all registered bots."""
        for bot_id, bot in list(self.bots.items()):
            if bot.status != "RUNNING":
                continue

            try:
                client = self.get_exchange_client(bot)
            except ValueError as e:
                logger.critical(
                    f"ZERO-TRUST SECURITY ENFORCEMENT: Halting bot '{bot_id}' immediately: {e}"
                )
                bot.status = "STOPPED"
                if self._bot_service:
                    self._bot_service.bot_repository.update_status(bot_id, "STOPPED")
                    self._bot_service.capital_repository.record_event(
                        bot_id=bot_id,
                        event_type="SECURITY_HALT",
                        details=str(e),
                    )
                else:
                    try:
                        self.capital_repo.record_event(
                            bot_id=bot_id,
                            event_type="SECURITY_HALT",
                            details=str(e),
                        )
                    except Exception as err:
                        logger.error(f"Failed to persist security halt event for bot '{bot_id}': {err}")

                self.event_bus.publish(
                    DomainEvent(
                        event_type="SECURITY_ALERT",
                        bot_id=bot_id,
                        data={
                            "level": "CRITICAL",
                            "message": str(e),
                            "status": "STOPPED",
                        },
                    )
                )
                continue

            # 1. External Balance Reconciliation for live trading
            if not bot.dry_run and client is not None:
                await self._reconcile_kucoin_balance(bot_id, bot, client=client)

            # 2. Read market state strictly from PostgreSQL (Zero KuCoin market calls)
            df_raw = self.candle_repo.get_candles_df(bot.config.symbol, "1h", limit=2000)
            if df_raw.empty or len(df_raw) < 50:
                continue

            df = TechnicalIndicators.apply_all(df_raw)
            latest_row = df.iloc[-1]
            current_ts = int(latest_row["timestamp"])
            current_price = float(latest_row["close"])
            high_price = float(latest_row["high"])
            low_price = float(latest_row["low"])

            # 3. Reconcile resting limit orders
            await self._reconcile_resting_orders(bot_id, bot, current_price, high_price, low_price, current_ts, client=client)

            # 4. Strategy evaluation on PostgreSQL data
            strat = self._get_strategy(bot_id, bot.strategy_name, bot.config)
            portfolio = PortfolioState(
                symbol=bot.config.symbol,
                total_budget=bot.config.budget,
                available_usdt=bot.available_usdt,
                active_tranches=bot.active_tranches,
                completed_tranches=bot.completed_tranches,
                total_realized_profit=bot.total_realized_profit,
                total_withdrawn_amount=bot.total_withdrawn_amount,
                total_deposited_amount=bot.total_deposited_amount,
            )

            signals = strat.evaluate(latest_row, portfolio)

            # 5. Process Limit Order Signals
            for sig in signals:
                if sig.signal_type == SignalType.BUY_TRANCHE:
                    await self._handle_buy_signal(bot_id, bot, sig, current_ts, client=client)

            # 6. Publish status telemetry event
            invested = sum(t.allocated_budget for t in bot.active_tranches)
            total_equity = bot.available_usdt + invested
            self.event_bus.publish(
                DomainEvent(
                    event_type="BOT_STATUS_UPDATED",
                    bot_id=bot_id,
                    data={
                        "available_usdt": round(bot.available_usdt, 2),
                        "invested_usdt": round(invested, 2),
                        "total_equity_usdt": round(total_equity, 2),
                        "active_tranches": len(bot.active_tranches),
                        "latest_price": current_price,
                    },
                )
            )

    async def _handle_buy_signal(self, bot_id: str, bot: BotInstance, sig: Any, current_ts: int, client: Optional[Any] = None) -> None:
        """Places resting BUY LIMIT order on KuCoin orderbook."""
        tranche_idx = sig.tranche_index
        already_active = any(t.tranche_index == tranche_idx and t.status == TrancheStatus.ACTIVE for t in bot.active_tranches)
        if already_active:
            return

        bot_pending = self._pending_buy_orders.setdefault(bot_id, {})
        if tranche_idx in bot_pending:
            return  # Limit buy order already resting on book

        req_budget = sig.allocated_usdt
        if bot.available_usdt < req_budget or req_budget < 10.0:
            return

        buy_price = sig.price
        fee = req_budget * self.fee_rate
        net_budget = req_budget - fee
        amount = net_budget / buy_price

        client = client or self.get_exchange_client(bot)
        order_id = f"sim_buy_{bot_id}_{tranche_idx}_{current_ts}"
        if not bot.dry_run and client is not None:
            try:
                loop = asyncio.get_running_loop()
                real_order = await loop.run_in_executor(
                    None,
                    lambda: client.create_order(
                        symbol=bot.config.symbol,
                        side="buy",
                        order_type="limit",
                        amount=amount,
                        price=buy_price,
                    ),
                )
                order_id = str(real_order.get("id"))
                logger.info(f"Placed resting BUY LIMIT order on KuCoin: {order_id} @ {buy_price:.2f}")
            except Exception as e:
                logger.error(f"Error submitting resting BUY LIMIT order to KuCoin: {e}", exc_info=True)
                return

        bot_pending[tranche_idx] = order_id
        order_record = Order(
            id=order_id,
            bot_id=bot_id,
            symbol=bot.config.symbol,
            side=OrderSide.BUY,
            order_type=OrderType.LIMIT,
            price=buy_price,
            amount=amount,
            status=OrderStatus.OPEN,
            fee=fee,
            created_at=current_ts,
        )
        self.order_repo.save_order(order_record)

    async def _reconcile_resting_orders(
        self, bot_id: str, bot: BotInstance, current_price: float, high_price: float, low_price: float, current_ts: int, client: Optional[Any] = None
    ) -> None:
        """Reconciles resting BUY and SELL limit orders on KuCoin book."""
        client = client or self.get_exchange_client(bot)

        # 1. Reconcile resting BUY limit orders
        bot_buys = self._pending_buy_orders.setdefault(bot_id, {})
        for tranche_idx, order_id in list(bot_buys.items()):
            filled = False
            fill_price = None
            fill_amount = None

            if not bot.dry_run and client is not None:
                try:
                    loop = asyncio.get_running_loop()
                    order_data = await loop.run_in_executor(
                        None, lambda oid=order_id: client.fetch_order(oid, bot.config.symbol)
                    )
                    status = str(order_data.get("status", "")).lower()
                    if status in ("closed", "filled"):
                        filled = True
                        fill_price = float(order_data.get("average") or order_data.get("price") or 0.0)
                        fill_amount = float(order_data.get("filled") or order_data.get("amount") or 0.0)
                except Exception as e:
                    logger.warning(f"Could not verify resting buy order {order_id} on KuCoin: {e}")
            else:
                order_rec = self.order_repo.get_order(order_id)
                if order_rec and low_price <= order_rec["price"]:
                    filled = True
                    fill_price = order_rec["price"]
                    fill_amount = order_rec["amount"]

            if filled:
                del bot_buys[tranche_idx]
                await self._activate_filled_tranche(bot_id, bot, tranche_idx, order_id, fill_price, fill_amount, current_ts, client=client)

        # 2. Reconcile resting SELL limit orders (Take Profit)
        bot_sells = self._pending_sell_orders.setdefault(bot_id, {})
        for tranche_idx, order_id in list(bot_sells.items()):
            filled = False
            fill_price = None

            if not bot.dry_run and client is not None:
                try:
                    loop = asyncio.get_running_loop()
                    order_data = await loop.run_in_executor(
                        None, lambda oid=order_id: client.fetch_order(oid, bot.config.symbol)
                    )
                    status = str(order_data.get("status", "")).lower()
                    if status in ("closed", "filled"):
                        filled = True
                        fill_price = float(order_data.get("average") or order_data.get("price") or 0.0)
                except Exception as e:
                    logger.warning(f"Could not verify resting sell order {order_id} on KuCoin: {e}")
            else:
                order_rec = self.order_repo.get_order(order_id)
                if order_rec and high_price >= order_rec["price"]:
                    filled = True
                    fill_price = order_rec["price"]

            if filled:
                del bot_sells[tranche_idx]
                await self._close_filled_tranche(bot_id, bot, tranche_idx, order_id, fill_price, current_ts, client=client)

    async def _activate_filled_tranche(
        self, bot_id: str, bot: BotInstance, tranche_idx: int, order_id: str, fill_price: float, fill_amount: float, current_ts: int, client: Optional[Any] = None
    ) -> None:
        """Transitions filled buy order into an active tranche and places resting SELL LIMIT order."""
        client = client or self.get_exchange_client(bot)
        self.order_repo.update_order_status(order_id, "CLOSED", filled_at=current_ts)
        allocated_budget = fill_amount * fill_price
        target_tp = fill_price * (1.0 + bot.config.take_profit_pct / 100.0)
        fee = allocated_budget * self.fee_rate

        tranche = Tranche(
            bot_id=bot_id,
            symbol=bot.config.symbol,
            tranche_index=tranche_idx,
            allocated_budget=allocated_budget,
            buy_price=fill_price,
            amount=fill_amount,
            target_sell_price=target_tp,
            status=TrancheStatus.ACTIVE,
            buy_fee=fee,
            buy_timestamp=current_ts,
        )
        tranche_id = self.tranche_repo.save_tranche(tranche)
        tranche.id = tranche_id
        bot.active_tranches.append(tranche)
        bot.available_usdt -= allocated_budget

        self.capital_repo.record_event(
            bot_id=bot_id,
            event_type="BUY",
            details=f"Limit Buy filled T{tranche_idx} @ {fill_price:.2f}. Resting Sell TP placed @ {target_tp:.2f}",
        )

        # Emit domain event (Telegram and WebSocket decoupled via EventBus)
        self.event_bus.publish(
            DomainEvent(
                event_type="TRANCHE_BOUGHT",
                bot_id=bot_id,
                data={
                    "tranche_index": tranche_idx,
                    "symbol": bot.config.symbol,
                    "buy_price": fill_price,
                    "amount": fill_amount,
                    "allocated_budget": allocated_budget,
                    "target_sell_price": target_tp,
                    "is_dry_run": bot.dry_run,
                },
            )
        )

        # Immediately place resting SELL LIMIT order (Maker) on KuCoin
        sell_order_id = f"sim_sell_{bot_id}_{tranche_idx}_{current_ts}"
        if not bot.dry_run and client is not None:
            try:
                loop = asyncio.get_running_loop()
                real_order = await loop.run_in_executor(
                    None,
                    lambda: client.create_order(
                        symbol=bot.config.symbol,
                        side="sell",
                        order_type="limit",
                        amount=fill_amount,
                        price=target_tp,
                    ),
                )
                sell_order_id = str(real_order.get("id"))
                logger.info(f"Placed resting Take Profit SELL LIMIT order on KuCoin: {sell_order_id} @ {target_tp:.2f}")
            except Exception as e:
                logger.error(f"Error placing resting Take Profit SELL LIMIT order: {e}", exc_info=True)

        self._pending_sell_orders.setdefault(bot_id, {})[tranche_idx] = sell_order_id
        self.order_repo.save_order(
            Order(
                id=sell_order_id,
                bot_id=bot_id,
                symbol=bot.config.symbol,
                side=OrderSide.SELL,
                order_type=OrderType.LIMIT,
                price=target_tp,
                amount=fill_amount,
                status=OrderStatus.OPEN,
                created_at=current_ts,
            )
        )

    async def _close_filled_tranche(
        self, bot_id: str, bot: BotInstance, tranche_idx: int, order_id: str, fill_price: float, current_ts: int, client: Optional[Any] = None
    ) -> None:
        """Closes a tranche upon Take Profit limit fill, extracts cash, and cascades profit subsidies."""
        client = client or self.get_exchange_client(bot)
        self.order_repo.update_order_status(order_id, "CLOSED", filled_at=current_ts)
        target = next((t for t in bot.active_tranches if t.tranche_index == tranche_idx), None)
        if not target:
            return

        revenue_gross = target.amount * fill_price
        sell_fee = revenue_gross * self.fee_rate
        revenue_net = revenue_gross - sell_fee
        realized_profit = revenue_net - target.allocated_budget

        target.actual_sell_price = fill_price
        target.sell_fee = sell_fee
        target.sell_timestamp = current_ts
        target.profit_usdt = realized_profit
        target.status = TrancheStatus.CLOSED

        self.tranche_repo.update_tranche(target)
        bot.active_tranches.remove(target)
        bot.completed_tranches.append(target)
        bot.available_usdt += revenue_net
        bot.total_realized_profit += realized_profit

        self.capital_repo.record_event(
            bot_id=bot_id,
            event_type="SELL",
            details=f"Take Profit Limit filled T{tranche_idx} @ {fill_price:.2f}. Profit: +{realized_profit:.2f} USDT",
        )

        # Cascading profit recycling to subsidize hung tranches
        if realized_profit > 0 and bot.active_tranches:
            remaining_subsidy = realized_profit * self.recycle_fraction
            hung_tranches = [t for t in bot.active_tranches if t.buy_price > target.buy_price]
            hung_tranches.sort(key=lambda t: t.buy_price, reverse=True)
            for hung in hung_tranches:
                if remaining_subsidy <= 0.01:
                    break
                floor_min = hung.buy_price * (1.0 - self.max_subsidized_discount_pct)
                max_reduction = hung.target_sell_price - floor_min
                if max_reduction > 0:
                    discount = min(remaining_subsidy, max_reduction)
                    hung.target_sell_price -= discount
                    hung.subsidized_satoshis += discount
                    remaining_subsidy -= discount
                    self.tranche_repo.update_tranche(hung)

                    # Update resting sell limit order in KuCoin book if open
                    await self._update_resting_sell_order_price(bot_id, bot, hung, client=client)

        # Emit domain event
        self.event_bus.publish(
            DomainEvent(
                event_type="TRANCHE_SOLD",
                bot_id=bot_id,
                data={
                    "tranche_index": tranche_idx,
                    "symbol": bot.config.symbol,
                    "sell_price": fill_price,
                    "profit_usdt": realized_profit,
                    "is_dry_run": bot.dry_run,
                },
            )
        )

    async def _update_resting_sell_order_price(self, bot_id: str, bot: BotInstance, hung_tranche: Tranche, client: Optional[Any] = None) -> None:
        """Cancels old resting sell order and posts new subsidized sell limit order."""
        client = client or self.get_exchange_client(bot)
        bot_sells = self._pending_sell_orders.get(bot_id, {})
        old_order_id = bot_sells.get(hung_tranche.tranche_index)
        if old_order_id and not bot.dry_run and client is not None:
            try:
                loop = asyncio.get_running_loop()
                await loop.run_in_executor(None, lambda: client.cancel_order(old_order_id, bot.config.symbol))
                self.order_repo.update_order_status(old_order_id, "CANCELED")
                new_order = await loop.run_in_executor(
                    None,
                    lambda: client.create_order(
                        symbol=bot.config.symbol,
                        side="sell",
                        order_type="limit",
                        amount=hung_tranche.amount,
                        price=hung_tranche.target_sell_price,
                    ),
                )
                new_id = str(new_order.get("id"))
                bot_sells[hung_tranche.tranche_index] = new_id
                self.order_repo.save_order(
                    Order(
                        id=new_id,
                        bot_id=bot_id,
                        symbol=bot.config.symbol,
                        side=OrderSide.SELL,
                        order_type=OrderType.LIMIT,
                        price=hung_tranche.target_sell_price,
                        amount=hung_tranche.amount,
                        status=OrderStatus.OPEN,
                        created_at=int(time.time() * 1000),
                    )
                )
                logger.info(f"Subsidized resting sell order updated: {new_id} @ {hung_tranche.target_sell_price:.2f}")
            except Exception as e:
                logger.warning(f"Could not replace subsidized sell order on KuCoin: {e}")

    async def _reconcile_kucoin_balance(self, bot_id: str, bot: BotInstance, client: Optional[Any] = None) -> None:
        """Reconciles KuCoin free USDT balance against local bot ledger."""
        client = client or self.get_exchange_client(bot)
        if client is None:
            return

        try:
            loop = asyncio.get_running_loop()
            real_balance = await loop.run_in_executor(None, lambda: client.fetch_free_balance("USDT"))
            diff = bot.available_usdt - real_balance
            if abs(diff) > 0.5:
                if diff > 0:
                    bot.total_withdrawn_amount += diff
                    bot.available_usdt = real_balance
                    self.capital_repo.record_transaction(
                        bot_id=bot_id,
                        type="WITHDRAWAL",
                        amount=diff,
                        available_after=real_balance,
                        reason="Auto-reconciliation: external withdrawal detected on KuCoin",
                    )
                else:
                    dep = abs(diff)
                    bot.total_deposited_amount += dep
                    bot.available_usdt = real_balance
                    self.capital_repo.record_transaction(
                        bot_id=bot_id,
                        type="DEPOSIT",
                        amount=dep,
                        available_after=real_balance,
                        reason="Auto-reconciliation: external deposit detected on KuCoin",
                    )
                self.event_bus.publish(
                    DomainEvent(
                        event_type="CAPITAL_ADJUSTED",
                        bot_id=bot_id,
                        data={
                            "type": "WITHDRAWAL" if diff > 0 else "DEPOSIT",
                            "amount": abs(diff),
                            "available_after": real_balance,
                            "reason": "KuCoin balance auto-reconciled",
                        },
                    )
                )
        except Exception as e:
            logger.error(f"Error checking balance on KuCoin for {bot_id}: {e}")

    async def start(self):
        """Starts background loop."""
        if self._running:
            return
        self._running = True
        self._task = asyncio.create_task(self._loop())
        logger.info("LiveRunner started with pure Resting Limit Order state machine.")

    async def _loop(self):
        while self._running:
            try:
                await self.run_cycle()
            except asyncio.CancelledError:
                break
            except Exception as e:
                logger.error(f"Error in LiveRunner loop: {e}", exc_info=True)

            try:
                await asyncio.sleep(self.interval_seconds)
            except asyncio.CancelledError:
                break

    def stop(self):
        """Stops background loop."""
        self._running = False
        if self._task and not self._task.done():
            self._task.cancel()
        logger.info("LiveRunner stopped.")
