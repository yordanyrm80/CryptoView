import logging
import os
import time
from typing import Dict, List, Optional

from src.core.event_bus import DomainEvent, EventBus
from src.domain.models import BotConfig, Tranche, TrancheStatus
from src.storage.bot_repository import BotRecord, BotRepository
from src.storage.database import DatabaseManager
from src.storage.tranche_repository import TrancheRepository
from src.storage.capital_repository import CapitalRepository
from src.storage.candle_repository import CandleRepository
from src.api.schemas import (
    BotEventResponse,
    BotSummaryResponse,
    CapitalTransactionItemResponse,
    CapitalTransactionResponse,
    CreateBotRequest,
    MetricsOverviewResponse,
    PlateauStatusResponse,
    TrancheResponse,
)
from src.core.regime_detector import MarketRegimeDetector, MarketRegime
from src.indicators.technical import TechnicalIndicators

logger = logging.getLogger(__name__)


class BotInstance:
    """Represents an active or dry-run instance of a trading bot."""

    def __init__(
        self,
        config: BotConfig,
        strategy_name: str,
        dry_run: bool = True,
    ):
        self.config = config
        self.strategy_name = strategy_name
        self.dry_run = dry_run

        self.status: str = "RUNNING"  # RUNNING, PAUSED, STOPPED
        self.active_tranches: List[Tranche] = []
        self.completed_tranches: List[Tranche] = []
        self.total_realized_profit: float = 0.0
        self.total_withdrawn_amount: float = 0.0
        self.total_deposited_amount: float = 0.0
        self.available_usdt: float = config.budget
        self.equity_history: List[float] = [config.budget]


class BotService:
    """Singleton service for managing bot lifecycle and metrics with PostgreSQL persistence."""

    _instance: Optional["BotService"] = None

    def __init__(
        self,
        tranche_repository: Optional[TrancheRepository] = None,
        capital_repository: Optional[CapitalRepository] = None,
        candle_repository: Optional[CandleRepository] = None,
        bot_repository: Optional[BotRepository] = None,
    ):
        db_mgr = DatabaseManager()
        self.db_manager = db_mgr
        self.tranche_repository = tranche_repository or TrancheRepository(db_mgr)
        self.capital_repository = capital_repository or CapitalRepository(db_mgr)
        self.candle_repository = candle_repository or CandleRepository(db_mgr)
        self.bot_repository = bot_repository or BotRepository(db_mgr)
        self.event_bus = EventBus.get_instance()

        self.bots: Dict[str, BotInstance] = {}
        self._init_default_bots()

    @classmethod
    def get_instance(cls) -> "BotService":
        if cls._instance is None:
            cls._instance = cls()
        return cls._instance

    def _hydrate_bot_financials(self, bot: BotInstance) -> None:
        """Hydrates active tranches, completed tranches and capital totals from PostgreSQL."""
        db_tranches = self.tranche_repository.get_active_tranches(bot.config.bot_id)
        bot.active_tranches = db_tranches
        invested = sum(t.allocated_budget for t in db_tranches)

        db_completed = self.tranche_repository.get_completed_tranches(bot.config.bot_id)
        bot.completed_tranches = db_completed
        bot.total_realized_profit = sum(t.profit_usdt for t in db_completed)

        dep, wit = self.capital_repository.get_totals(bot.config.bot_id)
        bot.total_deposited_amount = dep
        bot.total_withdrawn_amount = wit

        bot.available_usdt = max(0.0, bot.config.budget - invested) + (dep - wit)
        bot.equity_history = [bot.available_usdt + invested]

    def _init_default_bots(self):
        """Initializes bots from PostgreSQL database or seeds defaults on first run."""
        records = self.bot_repository.get_all_bots()
        if records:
            for rec in records:
                bot = BotInstance(
                    config=rec.config,
                    strategy_name=rec.strategy_name,
                    dry_run=rec.dry_run,
                )
                bot.status = rec.status
                self._hydrate_bot_financials(bot)
                self.bots[rec.bot_id] = bot
            return

        # First run: seed single official flagship bot and persist to PostgreSQL
        # Official Champion: Apex Titan (BTC Quantum Evolution)
        titan_cfg = BotConfig(
            bot_id="apex_titan_btc",
            symbol="BTC/USDT",
            budget=1000.0,
            take_profit_pct=4.5,
            max_tranches=8,
            tranche_weights=[0.30, 0.25, 0.20, 0.15, 0.10, 0.40, 0.35, 0.25],
            trailing_stop_pct=1.4,
            trend_weight=0.70,
        )
        titan_bot = BotInstance(
            config=titan_cfg,
            strategy_name="BtcQuantumEvolutionRegimeStrategy",
            dry_run=True,
        )
        titan_bot.status = "STOPPED"
        self._hydrate_bot_financials(titan_bot)
        self.bots[titan_cfg.bot_id] = titan_bot
        self.bot_repository.save_bot(
            bot_id=titan_cfg.bot_id,
            symbol=titan_cfg.symbol,
            strategy_name=titan_bot.strategy_name,
            budget=titan_cfg.budget,
            status="STOPPED",
            dry_run=titan_bot.dry_run,
            config=titan_cfg,
        )


    def list_bots(self) -> List[BotSummaryResponse]:
        """Returns summarized status for all tracked bots."""
        return [self._build_bot_summary(bot) for bot in self.bots.values()]

    def get_bot(self, bot_id: str) -> Optional[BotSummaryResponse]:
        """Returns details for a specific bot."""
        bot = self.bots.get(bot_id)
        if not bot:
            return None
        return self._build_bot_summary(bot)

    def get_bot_instance(self, bot_id: str) -> Optional[BotInstance]:
        """Returns the internal BotInstance object."""
        return self.bots.get(bot_id)

    def get_bot_tranches(self, bot_id: str) -> Optional[List[TrancheResponse]]:
        """Returns list of active and historical tranches for a bot."""
        bot = self.bots.get(bot_id)
        if not bot:
            return None

        tranches_db = self.tranche_repository.get_all_tranches(bot_id)
        if not tranches_db:
            all_tranches = bot.active_tranches + bot.completed_tranches
        else:
            all_tranches = tranches_db

        return [
            TrancheResponse(
                tranche_index=t.tranche_index,
                allocated_budget=t.allocated_budget,
                buy_price=t.buy_price,
                amount=t.amount,
                target_sell_price=t.target_sell_price,
                status=t.status.value if hasattr(t.status, "value") else str(t.status),
                profit_usdt=t.profit_usdt,
                buy_timestamp=t.buy_timestamp,
                sell_timestamp=t.sell_timestamp,
            )
            for t in all_tranches
        ]

    def create_bot(self, req: CreateBotRequest) -> BotSummaryResponse:
        """Creates and registers a new trading bot, persisting it to PostgreSQL."""
        if req.bot_id in self.bots:
            raise ValueError(f"Bot with ID '{req.bot_id}' already exists.")

        if not req.dry_run:
            if not (
                req.api_key
                and req.api_key.strip()
                and req.api_secret
                and req.api_secret.strip()
                and req.api_passphrase
                and req.api_passphrase.strip()
            ):
                raise ValueError(
                    "ZERO-TRUST SECURITY VIOLATION: Cannot deploy bot in LIVE mode without dedicated subaccount credentials (api_key, api_secret, api_passphrase). Fallback to default or master accounts is strictly prohibited."
                )

        cfg = BotConfig(
            bot_id=req.bot_id,
            symbol=req.symbol,
            budget=req.budget,
            take_profit_pct=req.take_profit_pct,
            max_tranches=req.max_tranches,
            tranche_weights=req.tranche_weights or [0.30, 0.25, 0.20, 0.15, 0.10],
            trailing_stop_pct=req.trailing_stop_pct,
            trend_weight=req.trend_weight,
            subaccount_name=req.subaccount_name,
            api_key=req.api_key,
            api_secret=req.api_secret,
            api_passphrase=req.api_passphrase,
        )
        instance = BotInstance(
            config=cfg,
            strategy_name=req.strategy_name,
            dry_run=req.dry_run,
        )
        self.bots[req.bot_id] = instance

        self.bot_repository.save_bot(
            bot_id=req.bot_id,
            symbol=req.symbol,
            strategy_name=req.strategy_name,
            budget=req.budget,
            status=instance.status,
            dry_run=req.dry_run,
            config=cfg,
        )

        self.capital_repository.record_event(
            bot_id=req.bot_id,
            event_type="CREATED",
            details=f"Bot deployed with strategy {req.strategy_name}, initial capital {req.budget} USDT (DryRun: {req.dry_run})",
        )

        self.event_bus.publish(
            DomainEvent(
                event_type="BOT_LIFECYCLE_CHANGED",
                bot_id=req.bot_id,
                data={"status": "CREATED", "symbol": req.symbol, "budget": req.budget},
            )
        )

        return self._build_bot_summary(instance)

    def create_test_bot(self, dry_run: bool = True, budget: float = 100.0) -> BotSummaryResponse:
        """Generates an official test bot to easily test and verify the entire system."""
        if not dry_run:
            raise ValueError(
                "ZERO-TRUST SECURITY VIOLATION: Instant test bots cannot be created in LIVE mode without explicit credentials."
            )
        test_id = f"test_bot_{int(time.time())}"
        cfg = BotConfig(
            bot_id=test_id,
            symbol="BTC/USDT",
            budget=budget,
            take_profit_pct=4.5,
            max_tranches=8,
            tranche_weights=[0.30, 0.25, 0.20, 0.15, 0.10, 0.40, 0.35, 0.25],
            trailing_stop_pct=1.4,
            trend_weight=0.70,
        )
        instance = BotInstance(
            config=cfg,
            strategy_name="BtcQuantumEvolutionRegimeStrategy",
            dry_run=dry_run,
        )
        instance.available_usdt = budget
        self.bots[test_id] = instance

        self.bot_repository.save_bot(
            bot_id=test_id,
            symbol="BTC/USDT",
            strategy_name="BtcQuantumEvolutionRegimeStrategy",
            budget=budget,
            status=instance.status,
            dry_run=dry_run,
            config=cfg,
        )

        self.capital_repository.record_event(
            bot_id=test_id,
            event_type="CREATED",
            details=f"Official test bot generated with budget {budget} USDT (DryRun: {dry_run})",
        )

        self.event_bus.publish(
            DomainEvent(
                event_type="BOT_LIFECYCLE_CHANGED",
                bot_id=test_id,
                data={"status": "CREATED", "symbol": "BTC/USDT", "budget": budget},
            )
        )

        return self._build_bot_summary(instance)

    def pause_bot(self, bot_id: str) -> bool:
        """Pauses new entries for a bot."""
        bot = self.bots.get(bot_id)
        if not bot:
            return False
        bot.status = "PAUSED"
        self.bot_repository.update_status(bot_id, "PAUSED")
        self.capital_repository.record_event(
            bot_id=bot_id,
            event_type="PAUSED",
            details="Bot paused. No new positions will be opened; active orders maintained.",
        )
        self.event_bus.publish(
            DomainEvent(
                event_type="BOT_LIFECYCLE_CHANGED",
                bot_id=bot_id,
                data={"status": "PAUSED"},
            )
        )
        return True

    def resume_bot(self, bot_id: str) -> bool:
        """Resumes normal operation for a bot."""
        bot = self.bots.get(bot_id)
        if not bot:
            return False
        if not bot.dry_run:
            if not (
                bot.config.api_key
                and bot.config.api_key.strip()
                and bot.config.api_secret
                and bot.config.api_secret.strip()
                and bot.config.api_passphrase
                and bot.config.api_passphrase.strip()
            ):
                raise ValueError(
                    f"CRITICAL ZERO-TRUST SECURITY VIOLATION: Cannot start/resume bot '{bot_id}' in LIVE mode without dedicated subaccount credentials (api_key, api_secret, api_passphrase). Fallback to default or master accounts is strictly prohibited."
                )
        bot.status = "RUNNING"
        self.bot_repository.update_status(bot_id, "RUNNING")
        self.capital_repository.record_event(
            bot_id=bot_id,
            event_type="RESUMED",
            details="Bot resumed to active RUNNING state.",
        )
        self.event_bus.publish(
            DomainEvent(
                event_type="BOT_LIFECYCLE_CHANGED",
                bot_id=bot_id,
                data={"status": "RUNNING"},
            )
        )
        return True

    def stop_bot(self, bot_id: str) -> bool:
        """Stops a bot."""
        bot = self.bots.get(bot_id)
        if not bot:
            return False
        bot.status = "STOPPED"
        self.bot_repository.update_status(bot_id, "STOPPED")
        self.capital_repository.record_event(
            bot_id=bot_id,
            event_type="STOPPED",
            details="Bot stopped completely.",
        )
        self.event_bus.publish(
            DomainEvent(
                event_type="BOT_LIFECYCLE_CHANGED",
                bot_id=bot_id,
                data={"status": "STOPPED"},
            )
        )
        return True

    def get_plateau_status(self, bot_id: str) -> PlateauStatusResponse:
        """Evaluates whether a bot is in a plateau phase and advises on capital injection."""
        bot = self.bots.get(bot_id)
        if not bot:
            raise ValueError(f"Bot '{bot_id}' not found.")

        active_count = len(bot.active_tranches)
        max_tranches = bot.config.max_tranches

        regime_str = "UNKNOWN"
        df_candles = self.candle_repository.get_candles_df(bot.config.symbol, "1h", limit=300)
        if not df_candles.empty and len(df_candles) >= 50:
            df_ind = TechnicalIndicators.apply_all(df_candles)
            latest_row = df_ind.iloc[-1]
            regime = MarketRegimeDetector.detect_regime(latest_row)
            regime_str = regime.value

        is_full_grid = (active_count >= max_tranches)
        is_dry_cash = (bot.available_usdt < (bot.config.budget * 0.05))

        is_plateau = is_full_grid or is_dry_cash

        if is_full_grid and bot.available_usdt < 50.0:
            rec = True
            advice = (
                "Bot en meseta profunda: todos los tramos base están ocupados y la liquidez se agotó. "
                "Incorporar capital fresco habilitará tramos de suelo (Floor Tranches) para reciclar ganancias y acelerar el rescate."
            )
        elif regime_str in ["PANIC_CAPITULATION", "RANGE"] and bot.available_usdt > 100.0:
            rec = True
            advice = "El mercado está en consolidación/pánico con capital disponible. Condiciones óptimas para acumulación."
        elif is_plateau:
            rec = True
            advice = "El bot se encuentra en fase de meseta. Añadir capital es seguro y aumentará la base de interés compuesto."
        else:
            rec = False
            advice = "El bot opera fluidamente con liquidez disponible. No es urgente inyectar capital en este momento."

        return PlateauStatusResponse(
            bot_id=bot_id,
            is_plateau_phase=is_plateau,
            active_tranches_count=active_count,
            max_tranches=max_tranches,
            available_usdt=round(bot.available_usdt, 2),
            current_market_regime=regime_str,
            capital_injection_recommended=rec,
            advice=advice,
        )

    def deposit_capital(self, bot_id: str, amount, reason: str = "Capital injection") -> CapitalTransactionResponse:
        """Injects fresh capital into a bot."""
        if hasattr(amount, "amount"):
            reason = amount.reason or reason
            amount = amount.amount
        bot = self.bots.get(bot_id)
        if not bot:
            raise ValueError(f"Bot '{bot_id}' not found.")
        if amount <= 0:
            raise ValueError("Deposit amount must be positive.")

        bot.available_usdt += amount
        bot.total_deposited_amount += amount

        ts = int(time.time() * 1000)
        self.capital_repository.record_transaction(
            bot_id=bot_id,
            type="DEPOSIT",
            amount=amount,
            available_after=bot.available_usdt,
            timestamp=ts,
            reason=reason,
        )
        self.capital_repository.record_event(
            bot_id=bot_id,
            event_type="DEPOSIT",
            details=f"Injected +{amount:.2f} USDT. New available balance: {bot.available_usdt:.2f} USDT. Reason: {reason}",
            timestamp=ts,
        )

        return CapitalTransactionResponse(
            bot_id=bot_id,
            type="DEPOSIT",
            amount=amount,
            available_usdt_after=round(bot.available_usdt, 2),
            total_deposited_usdt=round(bot.total_deposited_amount, 2),
            total_withdrawn_usdt=round(bot.total_withdrawn_amount, 2),
            timestamp=ts,
            message=f"Successfully deposited {amount:.2f} USDT.",
        )

    def withdraw_capital(self, bot_id: str, amount, reason: str = "Capital withdrawal") -> CapitalTransactionResponse:
        """Withdraws capital from bot's available USDT balance."""
        if hasattr(amount, "amount"):
            reason = amount.reason or reason
            amount = amount.amount
        bot = self.bots.get(bot_id)
        if not bot:
            raise ValueError(f"Bot '{bot_id}' not found.")
        if amount <= 0:
            raise ValueError("Withdrawal amount must be positive.")
        if amount > bot.available_usdt:
            raise ValueError(
                f"Fondos insuficientes: solicitado {amount:.2f} USDT, pero disponible es {bot.available_usdt:.2f} USDT."
            )

        bot.available_usdt -= amount
        bot.total_withdrawn_amount += amount

        ts = int(time.time() * 1000)
        self.capital_repository.record_transaction(
            bot_id=bot_id,
            type="WITHDRAWAL",
            amount=amount,
            available_after=bot.available_usdt,
            timestamp=ts,
            reason=reason,
        )
        self.capital_repository.record_event(
            bot_id=bot_id,
            event_type="WITHDRAWAL",
            details=f"Withdrawn -{amount:.2f} USDT. Remaining available balance: {bot.available_usdt:.2f} USDT. Reason: {reason}",
            timestamp=ts,
        )

        return CapitalTransactionResponse(
            bot_id=bot_id,
            type="WITHDRAWAL",
            amount=amount,
            available_usdt_after=round(bot.available_usdt, 2),
            total_deposited_usdt=round(bot.total_deposited_amount, 2),
            total_withdrawn_usdt=round(bot.total_withdrawn_amount, 2),
            timestamp=ts,
            message=f"Successfully withdrawn {amount:.2f} USDT.",
        )

    def get_capital_transactions(self, bot_id: str) -> List[CapitalTransactionItemResponse]:
        """Gets capital transactions history for a bot."""
        if bot_id not in self.bots:
            raise ValueError(f"Bot '{bot_id}' not found.")
        txs = self.capital_repository.get_transactions(bot_id)
        return [
            CapitalTransactionItemResponse(
                id=tx.id,
                bot_id=tx.bot_id,
                type=tx.type,
                amount=tx.amount,
                available_after=tx.available_after,
                timestamp=tx.timestamp,
                reason=tx.reason,
            )
            for tx in txs
        ]

    def get_bot_events(self, bot_id: str) -> List[BotEventResponse]:
        """Gets complete audit log events for a bot."""
        if bot_id not in self.bots:
            raise ValueError(f"Bot '{bot_id}' not found.")
        events = self.capital_repository.get_events(bot_id)
        return [
            BotEventResponse(
                id=ev.id,
                bot_id=ev.bot_id,
                event_type=ev.event_type,
                details=ev.details,
                timestamp=ev.timestamp,
            )
            for ev in events
        ]

    def get_portfolio_overview(self) -> MetricsOverviewResponse:
        """Calculates global metrics across all registered bots."""
        total_equity = 0.0
        total_cash_flow = 0.0
        active_bots = 0
        total_open_positions = 0.0
        total_trades = 0
        winning_trades = 0

        for bot in self.bots.values():
            if bot.status == "RUNNING":
                active_bots += 1

            invested = sum(t.allocated_budget for t in bot.active_tranches)
            total_open_positions += invested
            total_equity += (bot.available_usdt + invested)
            total_cash_flow += bot.total_realized_profit

            for t in bot.completed_tranches:
                total_trades += 1
                if t.profit_usdt > 0:
                    winning_trades += 1

        win_rate = (winning_trades / total_trades * 100.0) if total_trades > 0 else 0.0

        return MetricsOverviewResponse(
            total_portfolio_equity_usdt=round(total_equity, 2),
            total_cash_flow_extracted_usdt=round(total_cash_flow, 2),
            active_bots_count=active_bots,
            total_open_positions_usdt=round(total_open_positions, 2),
            system_win_rate_pct=round(win_rate, 2),
            total_closed_trades=total_trades,
        )

    def _build_bot_summary(self, bot: BotInstance) -> BotSummaryResponse:
        invested = sum(t.allocated_budget for t in bot.active_tranches)
        current_equity = bot.available_usdt + invested

        total_trades = len(bot.completed_tranches)
        winning_trades = sum(1 for t in bot.completed_tranches if t.profit_usdt > 0)
        win_rate = (winning_trades / total_trades * 100.0) if total_trades > 0 else 0.0

        plateau_info = self.get_plateau_status(bot.config.bot_id)

        return BotSummaryResponse(
            bot_id=bot.config.bot_id,
            symbol=bot.config.symbol,
            strategy_name=bot.strategy_name,
            budget=bot.config.budget,
            status=bot.status,
            dry_run=bot.dry_run,
            active_tranches_count=len(bot.active_tranches),
            invested_amount_usdt=round(invested, 2),
            available_usdt=round(bot.available_usdt, 2),
            total_realized_profit_usdt=round(bot.total_realized_profit, 2),
            total_withdrawn_usdt=round(bot.total_withdrawn_amount, 2),
            total_deposited_usdt=round(bot.total_deposited_amount, 2),
            current_equity_usdt=round(current_equity, 2),
            win_rate_pct=round(win_rate, 2),
            total_trades=total_trades,
            is_plateau_phase=plateau_info.is_plateau_phase,
            capital_injection_recommended=plateau_info.capital_injection_recommended,
            capital_injection_advice=plateau_info.advice,
            subaccount_name=bot.config.subaccount_name,
            has_custom_credentials=bool(bot.config.api_key and bot.config.api_secret),
        )
