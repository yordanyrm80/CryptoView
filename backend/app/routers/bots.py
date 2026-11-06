import json
import time
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional
from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field

from app.database import get_db_pool
from app.auth import verify_api_key
from app.services.bot_supervisor import DEFAULT_DISCORD_WEBHOOK_URL, send_discord_bot_embed
import ccxt.async_support as ccxt
from app.services.crypto import encrypt_secret, decrypt_secret

router = APIRouter(
    prefix="/api/v1",
    tags=["Quantitative Bots Fleet"],
    dependencies=[Depends(verify_api_key)],
)

_tables_initialized = False

# Official Champion Strategy & Recommended Configuration (Protected / Inviolable Seed)
CHAMPION_STRATEGY_NAME = "BtcQuantumEvolutionRegimeStrategy"
CHAMPION_SYMBOL = "BTC/USDT"
CHAMPION_TAKE_PROFIT_PCT = 4.5
CHAMPION_TRAILING_STOP_PCT = 1.4
CHAMPION_TREND_WEIGHT = 0.70
CHAMPION_BASE_MAX_TRANCHES = 5
CHAMPION_EXTRA_FLOOR_TRANCHES = 3
CHAMPION_MAX_TRANCHES = 8
CHAMPION_BASE_WEIGHTS = [0.30, 0.25, 0.20, 0.15, 0.10]
CHAMPION_FLOOR_WEIGHTS = [0.40, 0.35, 0.25]
CHAMPION_TRANCHE_WEIGHTS = [0.30, 0.25, 0.20, 0.15, 0.10, 0.40, 0.35, 0.25]
CHAMPION_T0_RSI_THRESHOLD = 48.0
CHAMPION_PANIC_RSI_THRESHOLD = 28.0
CHAMPION_ATR_MULTIPLIER = 1.5

RECOMMENDED_CONFIG_ID = "recommended_btc_quantum_evolution"

RECOMMENDED_QUANTUM_EVOLUTION_PARAMS: Dict[str, Any] = {
    "take_profit_pct": CHAMPION_TAKE_PROFIT_PCT,
    "trailing_stop_pct": CHAMPION_TRAILING_STOP_PCT,
    "trend_weight": CHAMPION_TREND_WEIGHT,
    "base_max_tranches": CHAMPION_BASE_MAX_TRANCHES,
    "extra_floor_tranches": CHAMPION_EXTRA_FLOOR_TRANCHES,
    "max_tranches": CHAMPION_MAX_TRANCHES,
    "base_tranche_weights": list(CHAMPION_BASE_WEIGHTS),
    "floor_tranche_weights": list(CHAMPION_FLOOR_WEIGHTS),
    "tranche_weights": list(CHAMPION_TRANCHE_WEIGHTS),
    "t0_rsi_threshold": CHAMPION_T0_RSI_THRESHOLD,
    "panic_rsi_threshold": CHAMPION_PANIC_RSI_THRESHOLD,
    "atr_multiplier": CHAMPION_ATR_MULTIPLIER,
    "enable_compounding": True,
    "macro_indicator": "ema_daily_200",
}

AVAILABLE_STRATEGIES = [
    {
        "strategy_name": CHAMPION_STRATEGY_NAME,
        "label": "Quantum Evolution Regime (Campeona Oficial)",
        "default_symbol": CHAMPION_SYMBOL,
        "recommended_config_id": RECOMMENDED_CONFIG_ID,
        "recommended_params": RECOMMENDED_QUANTUM_EVOLUTION_PARAMS,
    }
]


async def _ensure_bot_tables(conn) -> None:
    """Garantiza la presencia de configuraciones y semillas iniciales de la flota de bots."""
    global _tables_initialized
    if _tables_initialized:
        return

    now_ms = int(time.time() * 1000)

    # Ensure Discord notification settings are initialized with the default CryptoBot Webhook if empty
    notif_row = await conn.fetchrow("SELECT value_json FROM system_settings WHERE key = 'bot_notifications';")
    should_seed_notif = False
    if not notif_row or not notif_row["value_json"]:
        should_seed_notif = True
    else:
        try:
            parsed_notif = json.loads(notif_row["value_json"])
            if not (parsed_notif.get("discord_webhook_url") or "").strip():
                should_seed_notif = True
        except Exception:
            should_seed_notif = True

    if should_seed_notif:
        default_notif = {
            "discord_webhook_url": DEFAULT_DISCORD_WEBHOOK_URL,
            "notify_buys": True,
            "notify_sells": True,
            "notify_plateau": True,
        }
        await conn.execute(
            """
            INSERT INTO system_settings (key, value_json, updated_at)
            VALUES ('bot_notifications', $1, $2)
            ON CONFLICT (key) DO UPDATE SET
                value_json = EXCLUDED.value_json,
                updated_at = EXCLUDED.updated_at;
            """,
            json.dumps(default_notif),
            now_ms,
        )

    # Always guarantee the official protected "Configuración Recomendada" exists with exact champion parameters
    await conn.execute(
        """
        INSERT INTO strategy_configs (
            id, strategy_name, name, description, is_recommended, is_system, params_json, created_at, updated_at
        )
        VALUES ($1, $2, $3, $4, TRUE, TRUE, $5, $6, $7)
        ON CONFLICT (id) DO UPDATE SET
            strategy_name = EXCLUDED.strategy_name,
            name = EXCLUDED.name,
            description = EXCLUDED.description,
            is_recommended = TRUE,
            is_system = TRUE,
            params_json = EXCLUDED.params_json,
            updated_at = EXCLUDED.updated_at;
        """,
        RECOMMENDED_CONFIG_ID,
        CHAMPION_STRATEGY_NAME,
        "Configuración Recomendada",
        "Calibración ganadora oficial (+4,387% en 9 años): TP 4.5%, Trailing Stop 1.4%, Tendencia 70%, 5 Tramos Base [30/25/20/15/10%] + 3 Suelo [40/35/25%], RSI T0 48.0, RSI Pánico 28.0.",
        json.dumps(RECOMMENDED_QUANTUM_EVOLUTION_PARAMS),
        now_ms,
        now_ms,
    )

    # Seed default flagship bot if table is empty
    count = await conn.fetchval("SELECT COUNT(*) FROM bots;")
    if count == 0:
        default_cfg = {
            "bot_id": "apex_titan_btc",
            "symbol": "BTC/USDT",
            "budget": 1000.0,
            **RECOMMENDED_QUANTUM_EVOLUTION_PARAMS,
            "enabled": True,
            "subaccount_name": None,
            "api_key": None,
            "api_secret": None,
            "api_passphrase": None,
        }
        await conn.execute(
            """
            INSERT INTO bots (bot_id, symbol, strategy_name, budget, status, dry_run, config_json, created_at, updated_at)
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
            ON CONFLICT (bot_id) DO NOTHING;
            """,
            "apex_titan_btc",
            "BTC/USDT",
            "BtcQuantumEvolutionRegimeStrategy",
            1000.0,
            "STOPPED",
            True,
            json.dumps(default_cfg),
            now_ms,
            now_ms,
        )

    _tables_initialized = True


class CreateBotIn(BaseModel):
    bot_id: str
    symbol: str = CHAMPION_SYMBOL
    strategy_name: str = CHAMPION_STRATEGY_NAME
    budget: float
    dry_run: bool = True
    take_profit_pct: float = CHAMPION_TAKE_PROFIT_PCT
    trailing_stop_pct: float = CHAMPION_TRAILING_STOP_PCT
    trend_weight: float = CHAMPION_TREND_WEIGHT
    base_max_tranches: int = CHAMPION_BASE_MAX_TRANCHES
    extra_floor_tranches: int = CHAMPION_EXTRA_FLOOR_TRANCHES
    max_tranches: int = CHAMPION_MAX_TRANCHES
    base_tranche_weights: Optional[List[float]] = None
    floor_tranche_weights: Optional[List[float]] = None
    tranche_weights: Optional[List[float]] = None
    t0_rsi_threshold: float = CHAMPION_T0_RSI_THRESHOLD
    panic_rsi_threshold: float = CHAMPION_PANIC_RSI_THRESHOLD
    atr_multiplier: float = CHAMPION_ATR_MULTIPLIER
    enable_compounding: bool = True
    subaccount_name: Optional[str] = None
    api_key: Optional[str] = None
    api_secret: Optional[str] = None
    api_passphrase: Optional[str] = None


class UpdateBotStrategyConfigIn(BaseModel):
    take_profit_pct: float = CHAMPION_TAKE_PROFIT_PCT
    trailing_stop_pct: float = CHAMPION_TRAILING_STOP_PCT
    trend_weight: float = CHAMPION_TREND_WEIGHT
    base_max_tranches: int = CHAMPION_BASE_MAX_TRANCHES
    extra_floor_tranches: int = CHAMPION_EXTRA_FLOOR_TRANCHES
    max_tranches: Optional[int] = None
    base_tranche_weights: Optional[List[float]] = None
    floor_tranche_weights: Optional[List[float]] = None
    tranche_weights: Optional[List[float]] = None
    t0_rsi_threshold: float = CHAMPION_T0_RSI_THRESHOLD
    panic_rsi_threshold: float = CHAMPION_PANIC_RSI_THRESHOLD
    atr_multiplier: float = CHAMPION_ATR_MULTIPLIER
    enable_compounding: bool = True


class SaveStrategyConfigIn(BaseModel):
    id: Optional[str] = None
    strategy_name: str = CHAMPION_STRATEGY_NAME
    name: str
    description: Optional[str] = ""
    take_profit_pct: float = CHAMPION_TAKE_PROFIT_PCT
    trailing_stop_pct: float = CHAMPION_TRAILING_STOP_PCT
    trend_weight: float = CHAMPION_TREND_WEIGHT
    base_max_tranches: int = CHAMPION_BASE_MAX_TRANCHES
    extra_floor_tranches: int = CHAMPION_EXTRA_FLOOR_TRANCHES
    base_tranche_weights: Optional[List[float]] = None
    floor_tranche_weights: Optional[List[float]] = None
    t0_rsi_threshold: float = CHAMPION_T0_RSI_THRESHOLD
    panic_rsi_threshold: float = CHAMPION_PANIC_RSI_THRESHOLD
    atr_multiplier: float = CHAMPION_ATR_MULTIPLIER
    enable_compounding: bool = True


class CapitalActionIn(BaseModel):
    amount: Optional[float] = Field(default=None, description="Amount in USDT")
    amount_usdt: Optional[float] = Field(default=None, description="Alias for amount in USDT")
    reason: Optional[str] = Field(default="Ajuste operativo de capital")

    def resolved_amount(self) -> float:
        val = self.amount if self.amount is not None else (self.amount_usdt or 0.0)
        return float(val)


class BotNotificationsSettingsPayload(BaseModel):
    discord_webhook_url: str = ""
    notify_buys: bool = True
    notify_sells: bool = True
    notify_plateau: bool = True


class UpdateBotSubaccountIn(BaseModel):
    dry_run: bool = True
    subaccount_name: Optional[str] = None
    api_key: Optional[str] = None
    api_secret: Optional[str] = None
    api_passphrase: Optional[str] = None


async def _validate_subaccount_isolation(
    conn,
    current_bot_id: str,
    subaccount_name: Optional[str],
    api_key: Optional[str],
    dry_run: bool,
) -> None:
    """
    Garantiza la regla institucional '1 Bot = 1 Subcuenta Dedicada':
    - En modo real (dry_run=False), exige subaccount_name y credenciales completas.
    - Impide que dos bots compartan el mismo subaccount_name o la misma api_key.
    """
    clean_sub = (subaccount_name or "").strip()
    clean_key = (api_key or "").strip()

    if not dry_run and not clean_sub:
        raise HTTPException(
            status_code=400,
            detail="Regla de Aislamiento: Todo bot en modo real requiere un identificador de subcuenta dedicada (subaccount_name).",
        )

    other_rows = await conn.fetch(
        "SELECT bot_id, config_json FROM bots WHERE bot_id != $1;",
        current_bot_id,
    )
    for r in other_rows:
        other_id = r["bot_id"]
        raw = r["config_json"]
        other_cfg = json.loads(raw) if isinstance(raw, str) else (raw or {})
        other_sub = (other_cfg.get("subaccount_name") or "").strip()
        other_key = (other_cfg.get("api_key") or "").strip()

        if clean_sub and other_sub and clean_sub.lower() == other_sub.lower():
            raise HTTPException(
                status_code=409,
                detail=f"Conflicto de Aislamiento: La subcuenta '{clean_sub}' ya está asignada exclusivamente al bot '{other_id}'. Cada bot debe tener su propia subcuenta.",
            )
        if clean_key and other_key and clean_key == other_key:
            raise HTTPException(
                status_code=409,
                detail=f"Conflicto de Credenciales: La API Key ingresada ya pertenece a la subcuenta del bot '{other_id}'. Cada bot debe usar credenciales independientes.",
            )


async def _build_bot_summary_dict(conn, bot_row) -> Dict[str, Any]:
    bot_id = bot_row["bot_id"]
    symbol = (bot_row["symbol"] or CHAMPION_SYMBOL).strip().upper()
    budget = float(bot_row["budget"] or 0.0)
    strategy_name = bot_row["strategy_name"]
    raw_cfg = bot_row["config_json"]
    cfg = json.loads(raw_cfg) if isinstance(raw_cfg, str) else (raw_cfg or {})
    max_tranches = int(cfg.get("max_tranches") or (8 if strategy_name == "BtcQuantumEvolutionRegimeStrategy" else 5))

    latest_price_row = await conn.fetchrow(
        "SELECT close FROM market_candles WHERE exchange = 'kucoin' AND symbol = $1 ORDER BY time DESC LIMIT 1;",
        symbol,
    )
    latest_market_price = float(latest_price_row["close"]) if latest_price_row and latest_price_row["close"] else 0.0

    tranche_rows = await conn.fetch(
        "SELECT allocated_budget, amount, buy_fee, status, profit_usdt FROM tranches WHERE bot_id = $1;",
        bot_id,
    )

    active_tranches = 0
    invested_usdt = 0.0
    active_buy_fees = 0.0
    open_market_value = 0.0
    realized_pnl_usdt = 0.0
    closed_trades = 0
    winning_trades = 0

    for t in tranche_rows:
        st = (t["status"] or "").upper()
        if st in ("ACTIVE", "ACTIVO", "OPEN"):
            active_tranches += 1
            alloc = float(t["allocated_budget"] or 0.0)
            amt = float(t["amount"] or 0.0)
            fee = float(t["buy_fee"] or 0.0)
            invested_usdt += alloc
            active_buy_fees += fee
            open_market_value += (amt * latest_market_price) if latest_market_price > 0 and amt > 0 else alloc
        elif st in ("COMPLETED", "CLOSED", "SOLD", "CERRADO"):
            closed_trades += 1
            pnl = float(t["profit_usdt"] or 0.0)
            realized_pnl_usdt += pnl
            if pnl > 0:
                winning_trades += 1

    cap_rows = await conn.fetch(
        "SELECT type, COALESCE(SUM(amount), 0.0) AS total FROM capital_transactions WHERE bot_id = $1 GROUP BY type;",
        bot_id,
    )
    deposited = 0.0
    withdrawn = 0.0
    for c in cap_rows:
        t_type = (c["type"] or "").upper()
        if t_type == "DEPOSIT":
            deposited += float(c["total"] or 0.0)
        elif t_type == "WITHDRAWAL":
            withdrawn += float(c["total"] or 0.0)

    available_usdt = max(0.0, budget + realized_pnl_usdt - invested_usdt - active_buy_fees) + (deposited - withdrawn)
    current_equity_usdt = available_usdt + open_market_value
    unrealized_pnl_usdt = (open_market_value - invested_usdt - active_buy_fees) if active_tranches > 0 else 0.0
    win_rate_pct = (winning_trades / closed_trades * 100.0) if closed_trades > 0 else 0.0

    is_full_grid = active_tranches >= max_tranches
    is_dry_cash = available_usdt < (budget * 0.05)
    is_plateau = is_full_grid or is_dry_cash

    if is_full_grid and available_usdt < 50.0:
        rec = True
        advice = (
            "Capacidad de tramos base ocupada y reserva líquida baja. "
            "Se sugiere evaluar tramos de suelo o despliegue de instancia gemela en subcuenta aislada."
        )
    elif is_plateau:
        rec = True
        advice = "El bot se encuentra en fase de alta exposición. Revisa disponibilidad de liquidez si deseas ampliar tramos."
    else:
        rec = False
        advice = "Operativa fluida con liquidez disponible."

    has_creds = bool(cfg.get("api_key") and cfg.get("api_secret") and cfg.get("api_passphrase"))

    base_weights = cfg.get("base_tranche_weights") or list(CHAMPION_BASE_WEIGHTS)
    floor_weights = cfg.get("floor_tranche_weights") or list(CHAMPION_FLOOR_WEIGHTS)
    all_weights = cfg.get("tranche_weights") or (list(base_weights) + list(floor_weights))
    base_max = int(cfg.get("base_max_tranches") or len(base_weights) or CHAMPION_BASE_MAX_TRANCHES)
    extra_floor = int(
        cfg.get("extra_floor_tranches")
        if cfg.get("extra_floor_tranches") is not None
        else len(floor_weights)
    )

    return {
        "bot_id": bot_id,
        "symbol": symbol,
        "strategy_name": strategy_name,
        "budget": round(budget, 2),
        "allocated_budget": round(budget, 2),
        "status": bot_row["status"],
        "dry_run": bool(bot_row["dry_run"]),
        "active_tranches": active_tranches,
        "active_tranches_count": active_tranches,
        "max_tranches": max_tranches,
        "base_max_tranches": base_max,
        "extra_floor_tranches": extra_floor,
        "take_profit_pct": float(cfg.get("take_profit_pct", CHAMPION_TAKE_PROFIT_PCT)),
        "trailing_stop_pct": float(cfg.get("trailing_stop_pct", CHAMPION_TRAILING_STOP_PCT)),
        "trend_weight": float(cfg.get("trend_weight", CHAMPION_TREND_WEIGHT)),
        "t0_rsi_threshold": float(cfg.get("t0_rsi_threshold", CHAMPION_T0_RSI_THRESHOLD)),
        "panic_rsi_threshold": float(cfg.get("panic_rsi_threshold", CHAMPION_PANIC_RSI_THRESHOLD)),
        "atr_multiplier": float(cfg.get("atr_multiplier", CHAMPION_ATR_MULTIPLIER)),
        "enable_compounding": bool(cfg.get("enable_compounding", True)),
        "base_tranche_weights": base_weights,
        "floor_tranche_weights": floor_weights,
        "tranche_weights": all_weights,
        "invested_usdt": round(invested_usdt, 2),
        "invested_amount_usdt": round(invested_usdt, 2),
        "available_usdt": round(available_usdt, 2),
        "realized_pnl_usdt": round(realized_pnl_usdt, 2),
        "total_realized_profit_usdt": round(realized_pnl_usdt, 2),
        "unrealized_pnl_usdt": round(unrealized_pnl_usdt, 2),
        "total_deposited_usdt": round(deposited, 2),
        "total_withdrawn_usdt": round(withdrawn, 2),
        "current_equity_usdt": round(current_equity_usdt, 2),
        "win_rate_pct": round(win_rate_pct, 2),
        "total_trades": closed_trades,
        "current_market_regime": str(cfg.get("last_regime") or "RANGE"),
        "current_rsi": cfg.get("last_rsi"),
        "is_plateau_phase": is_plateau,
        "injection_recommended": rec,
        "capital_injection_recommended": rec,
        "injection_advice": advice,
        "capital_injection_advice": advice,
        "subaccount_name": cfg.get("subaccount_name"),
        "has_custom_credentials": has_creds,
    }


@router.get("/bots")
async def list_bots():
    pool = await get_db_pool()
    async with pool.acquire() as conn:
        await _ensure_bot_tables(conn)
        rows = await conn.fetch("SELECT * FROM bots ORDER BY created_at ASC;")
        return [await _build_bot_summary_dict(conn, r) for r in rows]


@router.get("/bots/metrics/overview")
@router.get("/metrics/overview")
async def get_fleet_metrics_overview():
    pool = await get_db_pool()
    async with pool.acquire() as conn:
        await _ensure_bot_tables(conn)
        rows = await conn.fetch("SELECT * FROM bots ORDER BY created_at ASC;")
        summaries = [await _build_bot_summary_dict(conn, r) for r in rows]

        total_bots = len(summaries)
        running_bots = sum(1 for b in summaries if b["status"].upper() == "RUNNING")
        total_allocated = sum(b["allocated_budget"] for b in summaries)
        total_available = sum(b["available_usdt"] for b in summaries)
        total_invested = sum(b["invested_usdt"] for b in summaries)
        total_realized = sum(b["realized_pnl_usdt"] for b in summaries)
        total_equity = sum(b["current_equity_usdt"] for b in summaries)

        closed_row = await conn.fetchrow(
            """
            SELECT
                COUNT(*) FILTER (WHERE UPPER(status) IN ('COMPLETED', 'CLOSED', 'SOLD', 'CERRADO')) AS closed_count,
                COUNT(*) FILTER (WHERE UPPER(status) IN ('COMPLETED', 'CLOSED', 'SOLD', 'CERRADO') AND profit_usdt > 0) AS win_count
            FROM tranches;
            """
        )
        closed_trades = int(closed_row["closed_count"] or 0) if closed_row else 0
        winning_trades = int(closed_row["win_count"] or 0) if closed_row else 0
        win_rate = (winning_trades / closed_trades * 100.0) if closed_trades > 0 else 0.0

        return {
            "total_bots": total_bots,
            "running_bots": running_bots,
            "active_bots_count": running_bots,
            "total_allocated_usdt": round(total_allocated, 2),
            "total_available_usdt": round(total_available, 2),
            "total_invested_usdt": round(total_invested, 2),
            "total_open_positions_usdt": round(total_invested, 2),
            "total_realized_pnl_usdt": round(total_realized, 2),
            "total_cashflow_usdt": round(total_realized, 2),
            "total_cash_flow_extracted_usdt": round(total_realized, 2),
            "total_equity_usdt": round(total_equity, 2),
            "total_portfolio_equity_usdt": round(total_equity, 2),
            "closed_trades": closed_trades,
            "total_closed_trades": closed_trades,
            "winning_trades": winning_trades,
            "win_rate_pct": round(win_rate, 2),
            "system_win_rate_pct": round(win_rate, 2),
        }


@router.get("/bots/settings/notifications")
@router.get("/settings")
async def get_bot_notification_settings():
    pool = await get_db_pool()
    async with pool.acquire() as conn:
        await _ensure_bot_tables(conn)
        row = await conn.fetchrow("SELECT value_json FROM system_settings WHERE key = 'bot_notifications';")
        if row and row["value_json"]:
            try:
                data = json.loads(row["value_json"])
                url = (data.get("discord_webhook_url") or "").strip() or DEFAULT_DISCORD_WEBHOOK_URL
                return {
                    "discord_webhook_url": url,
                    "notify_buys": bool(data.get("notify_buys", True)),
                    "notify_sells": bool(data.get("notify_sells", True)),
                    "notify_plateau": bool(data.get("notify_plateau", True)),
                }
            except Exception:
                pass
        return {
            "discord_webhook_url": DEFAULT_DISCORD_WEBHOOK_URL,
            "notify_buys": True,
            "notify_sells": True,
            "notify_plateau": True,
        }


@router.put("/bots/settings/notifications")
@router.put("/settings")
async def update_bot_notification_settings(payload: BotNotificationsSettingsPayload):
    pool = await get_db_pool()
    now_ms = int(time.time() * 1000)
    clean_dict = payload.model_dump()
    if not (clean_dict.get("discord_webhook_url") or "").strip():
        clean_dict["discord_webhook_url"] = DEFAULT_DISCORD_WEBHOOK_URL
    val_json = json.dumps(clean_dict)
    async with pool.acquire() as conn:
        await _ensure_bot_tables(conn)
        await conn.execute(
            """
            INSERT INTO system_settings (key, value_json, updated_at)
            VALUES ('bot_notifications', $1, $2)
            ON CONFLICT (key) DO UPDATE SET
                value_json = EXCLUDED.value_json,
                updated_at = EXCLUDED.updated_at;
            """,
            val_json,
            now_ms,
        )
    return clean_dict


@router.post("/bots/settings/notifications/test")
async def test_bot_discord_notification():
    pool = await get_db_pool()
    async with pool.acquire() as conn:
        await _ensure_bot_tables(conn)
        ok = await send_discord_bot_embed(
            conn,
            event_kind="TEST",
            title="🔔 Prueba de Canal Discord • CryptoView Quant Fleet",
            description="El canal de alertas de Discord está conectado y operativo 24/7 con el supervisor de Oracle Cloud.",
            color=0x2ECC71,
            fields=[
                {"name": "Motor", "value": "`BtcQuantumEvolutionRegimeStrategy`", "inline": True},
                {"name": "Estado", "value": "Activo 24/7 (Simulación y En Vivo)", "inline": True},
            ],
            footer_text="Apex Quant Engine • Test de Conectividad",
        )
        if not ok:
            raise HTTPException(status_code=502, detail="No se pudo entregar el mensaje de prueba al Webhook de Discord.")
        return {"ok": True, "message": "Mensaje de prueba enviado a Discord correctamente."}


@router.get("/bots/{bot_id}")
async def get_bot_by_id(bot_id: str):
    pool = await get_db_pool()
    async with pool.acquire() as conn:
        await _ensure_bot_tables(conn)
        row = await conn.fetchrow("SELECT * FROM bots WHERE bot_id = $1;", bot_id)
        if not row:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=f"Bot '{bot_id}' no encontrado.")
        return await _build_bot_summary_dict(conn, row)


@router.get("/bots/{bot_id}/tranches")
async def get_bot_tranches(bot_id: str):
    pool = await get_db_pool()
    async with pool.acquire() as conn:
        await _ensure_bot_tables(conn)
        bot_exists = await conn.fetchval("SELECT 1 FROM bots WHERE bot_id = $1;", bot_id)
        if not bot_exists:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=f"Bot '{bot_id}' no encontrado.")

        rows = await conn.fetch(
            "SELECT * FROM tranches WHERE bot_id = $1 ORDER BY tranche_index ASC, id ASC;",
            bot_id,
        )
        result = []
        for r in rows:
            buy_ts = r["buy_timestamp"]
            opened_iso = (
                datetime.fromtimestamp(buy_ts / 1000.0, tz=timezone.utc).isoformat()
                if buy_ts
                else None
            )
            buy_p = float(r["buy_price"] or 0.0)
            high_p = float(r.get("highest_price") or 0.0)
            if high_p <= 0.0:
                high_p = buy_p
            result.append(
                {
                    "id": r["id"],
                    "bot_id": r["bot_id"],
                    "tranche_index": r["tranche_index"],
                    "allocated_budget": float(r["allocated_budget"] or 0.0),
                    "buy_price": buy_p,
                    "amount": float(r["amount"] or 0.0),
                    "coin_amount": float(r["amount"] or 0.0),
                    "highest_price": high_p,
                    "target_sell_price": float(r["target_sell_price"] or 0.0),
                    "status": r["status"],
                    "profit_usdt": float(r["profit_usdt"] or 0.0),
                    "buy_fee": float(r["buy_fee"] or 0.0),
                    "buy_timestamp": buy_ts,
                    "opened_at": opened_iso,
                    "sell_timestamp": r["sell_timestamp"],
                }
            )
        return result


@router.get("/bots/{bot_id}/orders")
async def get_bot_orders(bot_id: str):
    pool = await get_db_pool()
    async with pool.acquire() as conn:
        await _ensure_bot_tables(conn)
        bot_exists = await conn.fetchval("SELECT 1 FROM bots WHERE bot_id = $1;", bot_id)
        if not bot_exists:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=f"Bot '{bot_id}' no encontrado.")
        rows = await conn.fetch(
            "SELECT * FROM orders WHERE bot_id = $1 ORDER BY created_at DESC LIMIT 200;",
            bot_id,
        )
        return [dict(r) for r in rows]


@router.get("/bots/strategies/catalog")
async def get_strategies_catalog():
    """Returns currently enabled strategies in the selector and their recommended parameters."""
    return AVAILABLE_STRATEGIES


@router.get("/bots/strategies/configs")
async def list_strategy_configs(strategy_name: Optional[str] = None):
    """Returns all saved strategy parameter configurations, with 'Configuración Recomendada' first."""
    pool = await get_db_pool()
    async with pool.acquire() as conn:
        await _ensure_bot_tables(conn)
        if strategy_name:
            rows = await conn.fetch(
                """
                SELECT * FROM strategy_configs
                WHERE strategy_name = $1
                ORDER BY is_recommended DESC, is_system DESC, created_at ASC;
                """,
                strategy_name.strip(),
            )
        else:
            rows = await conn.fetch(
                """
                SELECT * FROM strategy_configs
                ORDER BY is_recommended DESC, is_system DESC, created_at ASC;
                """
            )
        result = []
        for r in rows:
            raw_params = r["params_json"]
            params = json.loads(raw_params) if isinstance(raw_params, str) else (raw_params or {})
            result.append(
                {
                    "id": r["id"],
                    "strategy_name": r["strategy_name"],
                    "name": r["name"],
                    "description": r["description"] or "",
                    "is_recommended": bool(r["is_recommended"]),
                    "is_system": bool(r["is_system"]),
                    "params": params,
                    "created_at": r["created_at"],
                    "updated_at": r["updated_at"],
                }
            )
        return result


@router.post("/bots/strategies/configs", status_code=status.HTTP_201_CREATED)
async def save_strategy_config(req: SaveStrategyConfigIn):
    """Saves a custom strategy configuration preset without altering the protected Recommended Configuration."""
    clean_name = req.name.strip()
    if not clean_name:
        raise HTTPException(status_code=400, detail="El nombre de la configuración es obligatorio.")

    if clean_name.lower() in ("configuración recomendada", "configuracion recomendada") or req.id == RECOMMENDED_CONFIG_ID:
        raise HTTPException(
            status_code=400,
            detail="La 'Configuración Recomendada' oficial está protegida y es inmodificable. Usa otro nombre para guardar tu configuración personalizada.",
        )

    base_weights = req.base_tranche_weights or list(CHAMPION_BASE_WEIGHTS)
    floor_weights = req.floor_tranche_weights or list(CHAMPION_FLOOR_WEIGHTS)
    base_max = int(req.base_max_tranches or len(base_weights))
    extra_floor = int(req.extra_floor_tranches if req.extra_floor_tranches is not None else len(floor_weights))
    max_tranches = base_max + extra_floor
    tranche_weights = list(base_weights[:base_max]) + list(floor_weights[:extra_floor])

    params = {
        "take_profit_pct": float(req.take_profit_pct),
        "trailing_stop_pct": float(req.trailing_stop_pct),
        "trend_weight": float(req.trend_weight),
        "base_max_tranches": base_max,
        "extra_floor_tranches": extra_floor,
        "max_tranches": max_tranches,
        "base_tranche_weights": list(base_weights[:base_max]),
        "floor_tranche_weights": list(floor_weights[:extra_floor]),
        "tranche_weights": tranche_weights,
        "t0_rsi_threshold": float(req.t0_rsi_threshold),
        "panic_rsi_threshold": float(req.panic_rsi_threshold),
        "atr_multiplier": float(req.atr_multiplier),
        "enable_compounding": bool(req.enable_compounding),
        "macro_indicator": "ema_daily_200",
    }

    now_ms = int(time.time() * 1000)
    config_id = (req.id or "").strip() or f"cfg_{int(time.time() * 1000)}"

    pool = await get_db_pool()
    async with pool.acquire() as conn:
        await _ensure_bot_tables(conn)
        existing = await conn.fetchrow("SELECT is_system FROM strategy_configs WHERE id = $1;", config_id)
        if existing and existing["is_system"]:
            raise HTTPException(
                status_code=403,
                detail="No se puede sobrescribir una configuración oficial del sistema.",
            )

        await conn.execute(
            """
            INSERT INTO strategy_configs (
                id, strategy_name, name, description, is_recommended, is_system, params_json, created_at, updated_at
            )
            VALUES ($1, $2, $3, $4, FALSE, FALSE, $5, $6, $7)
            ON CONFLICT (id) DO UPDATE SET
                name = EXCLUDED.name,
                description = EXCLUDED.description,
                params_json = EXCLUDED.params_json,
                updated_at = EXCLUDED.updated_at;
            """,
            config_id,
            req.strategy_name.strip() or CHAMPION_STRATEGY_NAME,
            clean_name,
            (req.description or "").strip(),
            json.dumps(params),
            now_ms,
            now_ms,
        )

        return {
            "id": config_id,
            "strategy_name": req.strategy_name.strip() or CHAMPION_STRATEGY_NAME,
            "name": clean_name,
            "description": (req.description or "").strip(),
            "is_recommended": False,
            "is_system": False,
            "params": params,
            "created_at": now_ms,
            "updated_at": now_ms,
        }


@router.delete("/bots/strategies/configs/{config_id}")
async def delete_strategy_config(config_id: str):
    """Deletes a custom strategy configuration. System/Recommended configs cannot be deleted."""
    if config_id == RECOMMENDED_CONFIG_ID:
        raise HTTPException(
            status_code=403,
            detail="La 'Configuración Recomendada' oficial es inviolable y no puede ser eliminada.",
        )

    pool = await get_db_pool()
    async with pool.acquire() as conn:
        await _ensure_bot_tables(conn)
        row = await conn.fetchrow("SELECT is_system, is_recommended FROM strategy_configs WHERE id = $1;", config_id)
        if not row:
            raise HTTPException(status_code=404, detail="Configuración no encontrada.")
        if row["is_system"] or row["is_recommended"]:
            raise HTTPException(
                status_code=403,
                detail="La 'Configuración Recomendada' oficial es inviolable y no puede ser eliminada.",
            )
        await conn.execute("DELETE FROM strategy_configs WHERE id = $1;", config_id)
        return {"deleted": True, "id": config_id}


@router.post("/bots", status_code=status.HTTP_201_CREATED)
@router.post("/bots/create", status_code=status.HTTP_200_OK)
async def create_bot(req: CreateBotIn):
    bot_id = req.bot_id.strip()
    if not bot_id:
        raise HTTPException(
            status_code=400,
            detail="El identificador del bot es obligatorio.",
        )

    symbol = (req.symbol or CHAMPION_SYMBOL).strip().upper()
    if "/" not in symbol:
        raise HTTPException(
            status_code=400,
            detail="El par de mercado debe tener formato BASE/QUOTE (ej. BTC/USDT).",
        )

    strategy_name = (req.strategy_name or CHAMPION_STRATEGY_NAME).strip()
    if strategy_name != CHAMPION_STRATEGY_NAME:
        raise HTTPException(
            status_code=400,
            detail=f"Actualmente solo está habilitada en el selector la estrategia ganadora: {CHAMPION_STRATEGY_NAME}.",
        )

    if req.budget <= 0:
        raise HTTPException(
            status_code=400,
            detail="El presupuesto asignado debe ser mayor a cero.",
        )

    clean_sub = (req.subaccount_name or "").strip() or None
    clean_key = (req.api_key or "").strip() or None
    clean_secret = (req.api_secret or "").strip() or None
    clean_pass = (req.api_passphrase or "").strip() or None

    if not req.dry_run:
        if not (clean_sub and clean_key and clean_secret and clean_pass):
            raise HTTPException(
                status_code=400,
                detail="Aislamiento de Subcuenta: Para desplegar un bot en modo real es obligatorio proporcionar Nombre de Subcuenta, API Key, Secret y Passphrase exclusivos.",
            )

    base_weights = req.base_tranche_weights or list(CHAMPION_BASE_WEIGHTS)
    floor_weights = req.floor_tranche_weights or list(CHAMPION_FLOOR_WEIGHTS)
    base_max = int(req.base_max_tranches or len(base_weights) or CHAMPION_BASE_MAX_TRANCHES)
    extra_floor = int(req.extra_floor_tranches if req.extra_floor_tranches is not None else len(floor_weights))
    if req.tranche_weights:
        all_weights = list(req.tranche_weights)
        max_tranches = int(req.max_tranches or len(all_weights))
    else:
        all_weights = list(base_weights[:base_max]) + list(floor_weights[:extra_floor])
        max_tranches = base_max + extra_floor

    pool = await get_db_pool()
    async with pool.acquire() as conn:
        await _ensure_bot_tables(conn)
        exists = await conn.fetchval("SELECT 1 FROM bots WHERE bot_id = $1;", bot_id)
        if exists:
            raise HTTPException(status_code=409, detail=f"Ya existe un bot registrado con el ID '{bot_id}'.")

        await _validate_subaccount_isolation(
            conn,
            current_bot_id=bot_id,
            subaccount_name=clean_sub,
            api_key=clean_key,
            dry_run=req.dry_run,
        )

        now_ms = int(time.time() * 1000)
        cfg = {
            "bot_id": bot_id,
            "symbol": symbol,
            "budget": req.budget,
            "take_profit_pct": float(req.take_profit_pct),
            "trailing_stop_pct": float(req.trailing_stop_pct),
            "trend_weight": float(req.trend_weight),
            "base_max_tranches": base_max,
            "extra_floor_tranches": extra_floor,
            "max_tranches": max_tranches,
            "base_tranche_weights": list(base_weights[:base_max]),
            "floor_tranche_weights": list(floor_weights[:extra_floor]),
            "tranche_weights": all_weights,
            "t0_rsi_threshold": float(req.t0_rsi_threshold),
            "panic_rsi_threshold": float(req.panic_rsi_threshold),
            "atr_multiplier": float(req.atr_multiplier),
            "enable_compounding": bool(req.enable_compounding),
            "macro_indicator": "ema_daily_200",
            "enabled": True,
            "subaccount_name": clean_sub,
            "api_key": encrypt_secret(clean_key) if clean_key else None,
            "api_secret": encrypt_secret(clean_secret) if clean_secret else None,
            "api_passphrase": encrypt_secret(clean_pass) if clean_pass else None,
        }

        await conn.execute(
            """
            INSERT INTO bots (bot_id, symbol, strategy_name, budget, status, dry_run, config_json, created_at, updated_at)
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9);
            """,
            bot_id,
            symbol,
            strategy_name,
            req.budget,
            "RUNNING",
            req.dry_run,
            json.dumps(cfg),
            now_ms,
            now_ms,
        )

        await conn.execute(
            """
            INSERT INTO bot_events (bot_id, event_type, details, timestamp)
            VALUES ($1, 'CREATED', $2, $3);
            """,
            bot_id,
            f"Bot registrado ({strategy_name}) en subcuenta '{clean_sub or 'Simulación'}' con capital inicial {req.budget:.2f} USDT (TP {req.take_profit_pct}%, TS {req.trailing_stop_pct}%, Tendencia {req.trend_weight*100:.0f}%)",
            now_ms,
        )

        row = await conn.fetchrow("SELECT * FROM bots WHERE bot_id = $1;", bot_id)
        return await _build_bot_summary_dict(conn, row)


@router.put("/bots/{bot_id}/config")
async def update_bot_strategy_config(bot_id: str, req: UpdateBotStrategyConfigIn):
    """Updates the strategy parameters of an existing bot (or applies the Recommended Configuration)."""
    pool = await get_db_pool()
    async with pool.acquire() as conn:
        await _ensure_bot_tables(conn)
        row = await conn.fetchrow("SELECT * FROM bots WHERE bot_id = $1;", bot_id)
        if not row:
            raise HTTPException(status_code=404, detail=f"Bot '{bot_id}' no encontrado.")

        cfg = json.loads(row["config_json"]) if isinstance(row["config_json"], str) else (row["config_json"] or {})

        base_weights = req.base_tranche_weights or cfg.get("base_tranche_weights") or list(CHAMPION_BASE_WEIGHTS)
        floor_weights = req.floor_tranche_weights or cfg.get("floor_tranche_weights") or list(CHAMPION_FLOOR_WEIGHTS)
        base_max = int(req.base_max_tranches or len(base_weights) or CHAMPION_BASE_MAX_TRANCHES)
        extra_floor = int(req.extra_floor_tranches if req.extra_floor_tranches is not None else len(floor_weights))
        if req.tranche_weights:
            all_weights = list(req.tranche_weights)
            max_tranches = int(req.max_tranches or len(all_weights))
        else:
            all_weights = list(base_weights[:base_max]) + list(floor_weights[:extra_floor])
            max_tranches = base_max + extra_floor

        cfg.update(
            {
                "take_profit_pct": float(req.take_profit_pct),
                "trailing_stop_pct": float(req.trailing_stop_pct),
                "trend_weight": float(req.trend_weight),
                "base_max_tranches": base_max,
                "extra_floor_tranches": extra_floor,
                "max_tranches": max_tranches,
                "base_tranche_weights": list(base_weights[:base_max]),
                "floor_tranche_weights": list(floor_weights[:extra_floor]),
                "tranche_weights": all_weights,
                "t0_rsi_threshold": float(req.t0_rsi_threshold),
                "panic_rsi_threshold": float(req.panic_rsi_threshold),
                "atr_multiplier": float(req.atr_multiplier),
                "enable_compounding": bool(req.enable_compounding),
            }
        )

        now_ms = int(time.time() * 1000)
        await conn.execute(
            "UPDATE bots SET config_json = $1, updated_at = $2 WHERE bot_id = $3;",
            json.dumps(cfg),
            now_ms,
            bot_id,
        )
        await conn.execute(
            "INSERT INTO bot_events (bot_id, event_type, details, timestamp) VALUES ($1, 'CONFIG_UPDATED', $2, $3);",
            bot_id,
            f"Parámetros de estrategia actualizados (TP: {req.take_profit_pct}%, TS: {req.trailing_stop_pct}%, Tendencia: {req.trend_weight*100:.0f}%, Tramos: {max_tranches}).",
            now_ms,
        )
        updated_row = await conn.fetchrow("SELECT * FROM bots WHERE bot_id = $1;", bot_id)
        return await _build_bot_summary_dict(conn, updated_row)


@router.put("/bots/{bot_id}/subaccount")
async def update_bot_subaccount(bot_id: str, req: UpdateBotSubaccountIn):
    clean_sub = (req.subaccount_name or "").strip() or None
    clean_key = (req.api_key or "").strip() or None
    clean_secret = (req.api_secret or "").strip() or None
    clean_pass = (req.api_passphrase or "").strip() or None

    if not req.dry_run and not (clean_sub and clean_key and clean_secret and clean_pass):
        raise HTTPException(
            status_code=400,
            detail="Para activar la ejecución real en la subcuenta es obligatorio proporcionar Nombre de Subcuenta, API Key, Secret y Passphrase.",
        )

    pool = await get_db_pool()
    async with pool.acquire() as conn:
        await _ensure_bot_tables(conn)
        row = await conn.fetchrow("SELECT * FROM bots WHERE bot_id = $1;", bot_id)
        if not row:
            raise HTTPException(status_code=404, detail=f"Bot '{bot_id}' no encontrado.")

        if row["status"].upper() == "RUNNING":
            raise HTTPException(
                status_code=400,
                detail="Detén o pausa el bot antes de modificar su subcuenta o modo de ejecución.",
            )

        cfg = json.loads(row["config_json"]) if isinstance(row["config_json"], str) else (row["config_json"] or {})
        effective_sub = clean_sub if clean_sub is not None else cfg.get("subaccount_name")
        effective_key = clean_key if clean_key is not None else cfg.get("api_key")

        await _validate_subaccount_isolation(
            conn,
            current_bot_id=bot_id,
            subaccount_name=effective_sub,
            api_key=effective_key,
            dry_run=req.dry_run,
        )

        cfg["subaccount_name"] = effective_sub
        if clean_key is not None:
            cfg["api_key"] = encrypt_secret(clean_key)
        if clean_secret is not None:
            cfg["api_secret"] = encrypt_secret(clean_secret)
        if clean_pass is not None:
            cfg["api_passphrase"] = encrypt_secret(clean_pass)

        now_ms = int(time.time() * 1000)
        await conn.execute(
            "UPDATE bots SET dry_run = $1, config_json = $2, updated_at = $3 WHERE bot_id = $4;",
            req.dry_run,
            json.dumps(cfg),
            now_ms,
            bot_id,
        )
        await conn.execute(
            "INSERT INTO bot_events (bot_id, event_type, details, timestamp) VALUES ($1, 'SUBACCOUNT_UPDATED', $2, $3);",
            bot_id,
            f"Subcuenta actualizada a '{effective_sub or 'Simulación'}' (DryRun: {req.dry_run}).",
            now_ms,
        )
        updated_row = await conn.fetchrow("SELECT * FROM bots WHERE bot_id = $1;", bot_id)
        return await _build_bot_summary_dict(conn, updated_row)


async def _change_bot_status(bot_id: str, new_status: str, event_type: str, details: str):
    pool = await get_db_pool()
    async with pool.acquire() as conn:
        await _ensure_bot_tables(conn)
        row = await conn.fetchrow("SELECT * FROM bots WHERE bot_id = $1;", bot_id)
        if not row:
            raise HTTPException(status_code=404, detail=f"Bot '{bot_id}' no encontrado.")

        if new_status == "RUNNING" and not row["dry_run"]:
            cfg = json.loads(row["config_json"]) if isinstance(row["config_json"], str) else (row["config_json"] or {})
            if not (cfg.get("subaccount_name") and cfg.get("api_key") and cfg.get("api_secret") and cfg.get("api_passphrase")):
                raise HTTPException(
                    status_code=400,
                    detail=f"No se puede iniciar '{bot_id}' en modo real sin un identificador de subcuenta dedicada y sus credenciales completas.",
                )
            await _validate_subaccount_isolation(
                conn,
                current_bot_id=bot_id,
                subaccount_name=cfg.get("subaccount_name"),
                api_key=cfg.get("api_key"),
                dry_run=False,
            )

        now_ms = int(time.time() * 1000)
        await conn.execute(
            "UPDATE bots SET status = $1, updated_at = $2 WHERE bot_id = $3;",
            new_status,
            now_ms,
            bot_id,
        )
        await conn.execute(
            "INSERT INTO bot_events (bot_id, event_type, details, timestamp) VALUES ($1, $2, $3, $4);",
            bot_id,
            event_type,
            details,
            now_ms,
        )
        await send_discord_bot_embed(
            conn,
            event_kind="STATUS",
            title=f"ℹ️ {bot_id} ➔ {new_status}",
            description=f"_{details}_",
            color=0x3498DB,
            fields=[],
        )
        return {"status": new_status, "bot_id": bot_id, "message": details}


@router.post("/bots/{bot_id}/start")
async def start_bot(bot_id: str):
    return await _change_bot_status(bot_id, "RUNNING", "STARTED", f"Bot '{bot_id}' iniciado.")


@router.post("/bots/{bot_id}/resume")
async def resume_bot(bot_id: str):
    return await _change_bot_status(bot_id, "RUNNING", "RESUMED", f"Bot '{bot_id}' reanudado.")


@router.post("/bots/{bot_id}/pause")
async def pause_bot(bot_id: str):
    return await _change_bot_status(bot_id, "PAUSED", "PAUSED", f"Bot '{bot_id}' pausado.")


@router.post("/bots/{bot_id}/stop")
async def stop_bot(bot_id: str):
    return await _change_bot_status(bot_id, "STOPPED", "STOPPED", f"Bot '{bot_id}' detenido.")


@router.post("/bots/{bot_id}/deposit")
async def deposit_bot_capital(bot_id: str, req: CapitalActionIn):
    amount = req.resolved_amount()
    if amount <= 0:
        raise HTTPException(status_code=400, detail="El monto a depositar debe ser mayor a cero.")

    pool = await get_db_pool()
    async with pool.acquire() as conn:
        await _ensure_bot_tables(conn)
        row = await conn.fetchrow("SELECT * FROM bots WHERE bot_id = $1;", bot_id)
        if not row:
            raise HTTPException(status_code=404, detail=f"Bot '{bot_id}' no encontrado.")

        summary = await _build_bot_summary_dict(conn, row)
        available_after = summary["available_usdt"] + amount
        now_ms = int(time.time() * 1000)

        await conn.execute(
            """
            INSERT INTO capital_transactions (bot_id, type, amount, available_after, timestamp, reason)
            VALUES ($1, 'DEPOSIT', $2, $3, $4, $5);
            """,
            bot_id,
            amount,
            available_after,
            now_ms,
            req.reason or "Asignación operativa de capital",
        )
        await conn.execute(
            """
            INSERT INTO bot_events (bot_id, event_type, details, timestamp)
            VALUES ($1, 'DEPOSIT', $2, $3);
            """,
            bot_id,
            f"Asignación de +{amount:.2f} USDT. Disponible posterior: {available_after:.2f} USDT.",
            now_ms,
        )
        await send_discord_bot_embed(
            conn,
            event_kind="CAPITAL",
            title=f"💳 {bot_id}: DEPOSIT ${amount:,.2f} USDT",
            description=f"_{req.reason or 'Asignación operativa de capital'}_",
            color=0x9B59B6,
            fields=[],
        )

        return {
            "bot_id": bot_id,
            "type": "DEPOSIT",
            "amount": round(amount, 2),
            "available_usdt_after": round(available_after, 2),
            "timestamp": now_ms,
            "message": "Capital asignado correctamente.",
        }


@router.post("/bots/{bot_id}/withdraw")
async def withdraw_bot_capital(bot_id: str, req: CapitalActionIn):
    amount = req.resolved_amount()
    if amount <= 0:
        raise HTTPException(status_code=400, detail="El monto a retirar debe ser mayor a cero.")

    pool = await get_db_pool()
    async with pool.acquire() as conn:
        await _ensure_bot_tables(conn)
        row = await conn.fetchrow("SELECT * FROM bots WHERE bot_id = $1;", bot_id)
        if not row:
            raise HTTPException(status_code=404, detail=f"Bot '{bot_id}' no encontrado.")

        summary = await _build_bot_summary_dict(conn, row)
        if amount > summary["available_usdt"] + 1e-6:
            raise HTTPException(
                status_code=400,
                detail=f"Liquidez libre insuficiente ({summary['available_usdt']:.2f} USDT disponibles).",
            )

        available_after = max(0.0, summary["available_usdt"] - amount)
        now_ms = int(time.time() * 1000)

        await conn.execute(
            """
            INSERT INTO capital_transactions (bot_id, type, amount, available_after, timestamp, reason)
            VALUES ($1, 'WITHDRAWAL', $2, $3, $4, $5);
            """,
            bot_id,
            amount,
            available_after,
            now_ms,
            req.reason or "Retiro de liquidez a cuenta principal",
        )
        await conn.execute(
            """
            INSERT INTO bot_events (bot_id, event_type, details, timestamp)
            VALUES ($1, 'WITHDRAWAL', $2, $3);
            """,
            bot_id,
            f"Retiro de -{amount:.2f} USDT. Disponible posterior: {available_after:.2f} USDT.",
            now_ms,
        )
        await send_discord_bot_embed(
            conn,
            event_kind="CAPITAL",
            title=f"💳 {bot_id}: WITHDRAWAL ${amount:,.2f} USDT",
            description=f"_{req.reason or 'Retiro de liquidez a cuenta principal'}_",
            color=0x9B59B6,
            fields=[],
        )

        return {
            "bot_id": bot_id,
            "type": "WITHDRAWAL",
            "amount": round(amount, 2),
            "available_usdt_after": round(available_after, 2),
            "total_deposited_usdt": round(summary["total_deposited_usdt"], 2),
            "total_withdrawn_usdt": round(summary["total_withdrawn_usdt"] + amount, 2),
            "timestamp": now_ms,
            "message": "Retiro registrado correctamente.",
        }


@router.get("/bots/{bot_id}/plateau-status")
async def get_bot_plateau_status(bot_id: str):
    pool = await get_db_pool()
    async with pool.acquire() as conn:
        await _ensure_bot_tables(conn)
        row = await conn.fetchrow("SELECT * FROM bots WHERE bot_id = $1;", bot_id)
        if not row:
            raise HTTPException(status_code=404, detail=f"Bot '{bot_id}' no encontrado.")
        summary = await _build_bot_summary_dict(conn, row)
        return {
            "bot_id": bot_id,
            "is_plateau_phase": summary["is_plateau_phase"],
            "active_tranches_count": summary["active_tranches_count"],
            "max_tranches": summary["max_tranches"],
            "available_usdt": summary["available_usdt"],
            "current_market_regime": summary.get("current_market_regime") or "RANGE",
            "capital_injection_recommended": summary["capital_injection_recommended"],
            "advice": summary["capital_injection_advice"],
        }


@router.get("/bots/{bot_id}/transactions")
async def get_bot_capital_transactions(bot_id: str):
    pool = await get_db_pool()
    async with pool.acquire() as conn:
        await _ensure_bot_tables(conn)
        bot_exists = await conn.fetchval("SELECT 1 FROM bots WHERE bot_id = $1;", bot_id)
        if not bot_exists:
            raise HTTPException(status_code=404, detail=f"Bot '{bot_id}' no encontrado.")
        rows = await conn.fetch(
            "SELECT id, bot_id, type, amount, available_after, timestamp, reason FROM capital_transactions WHERE bot_id = $1 ORDER BY timestamp DESC;",
            bot_id,
        )
        return [dict(r) for r in rows]


@router.get("/bots/{bot_id}/events")
async def get_bot_audit_events(bot_id: str):
    pool = await get_db_pool()
    async with pool.acquire() as conn:
        await _ensure_bot_tables(conn)
        bot_exists = await conn.fetchval("SELECT 1 FROM bots WHERE bot_id = $1;", bot_id)
        if not bot_exists:
            raise HTTPException(status_code=404, detail=f"Bot '{bot_id}' no encontrado.")
        rows = await conn.fetch(
            "SELECT id, bot_id, event_type, details, timestamp FROM bot_events WHERE bot_id = $1 ORDER BY timestamp DESC LIMIT 200;",
            bot_id,
        )
        return [dict(r) for r in rows]


@router.post("/bots/{bot_id}/reset-simulation")
async def reset_bot_simulation(bot_id: str):
    """Reinicia desde cero un bot que opere en simulación (dry_run=True)."""
    pool = await get_db_pool()
    async with pool.acquire() as conn:
        await _ensure_bot_tables(conn)
        row = await conn.fetchrow("SELECT * FROM bots WHERE bot_id = $1;", bot_id)
        if not row:
            raise HTTPException(status_code=404, detail=f"Bot '{bot_id}' no encontrado.")
        if not row["dry_run"]:
            raise HTTPException(status_code=400, detail="Solo se pueden reiniciar bots en modo Simulación.")
        if row["status"].upper() == "RUNNING":
            raise HTTPException(status_code=400, detail="Pausa o detén el bot antes de reiniciar la simulación.")

        now_ms = int(time.time() * 1000)
        async with conn.transaction():
            await conn.execute("DELETE FROM tranches WHERE bot_id = $1;", bot_id)
            await conn.execute("DELETE FROM orders WHERE bot_id = $1;", bot_id)
            await conn.execute("DELETE FROM capital_transactions WHERE bot_id = $1;", bot_id)

            cfg = json.loads(row["config_json"]) if isinstance(row["config_json"], str) else (row["config_json"] or {})
            cfg.pop("trend_highest_price", None)
            cfg.pop("last_regime", None)
            cfg.pop("last_rsi", None)
            cfg.pop("last_price", None)

            await conn.execute(
                "UPDATE bots SET config_json = $1, updated_at = $2 WHERE bot_id = $3;",
                json.dumps(cfg),
                now_ms,
                bot_id,
            )
            await conn.execute(
                "INSERT INTO bot_events (bot_id, event_type, details, timestamp) VALUES ($1, 'SIMULATION_RESET', 'Simulación reiniciada a valores iniciales.', $2);",
                bot_id,
                now_ms,
            )

        updated_row = await conn.fetchrow("SELECT * FROM bots WHERE bot_id = $1;", bot_id)
        return await _build_bot_summary_dict(conn, updated_row)


@router.delete("/bots/{bot_id}")
async def delete_bot(bot_id: str):
    """Elimina una instancia de bot detenida y sus registros operativos asociados."""
    pool = await get_db_pool()
    async with pool.acquire() as conn:
        await _ensure_bot_tables(conn)
        row = await conn.fetchrow("SELECT * FROM bots WHERE bot_id = $1;", bot_id)
        if not row:
            raise HTTPException(status_code=404, detail=f"Bot '{bot_id}' no encontrado.")
        if row["status"].upper() == "RUNNING":
            raise HTTPException(status_code=400, detail="No puedes eliminar un bot activo. Deténlo primero.")

        async with conn.transaction():
            await conn.execute("DELETE FROM tranches WHERE bot_id = $1;", bot_id)
            await conn.execute("DELETE FROM orders WHERE bot_id = $1;", bot_id)
            await conn.execute("DELETE FROM capital_transactions WHERE bot_id = $1;", bot_id)
            await conn.execute("DELETE FROM bot_events WHERE bot_id = $1;", bot_id)
            await conn.execute("DELETE FROM bots WHERE bot_id = $1;", bot_id)

        return {"deleted": True, "bot_id": bot_id, "message": f"Bot '{bot_id}' eliminado correctamente."}


class UpdateExchangeProxyIn(BaseModel):
    proxy_url: str = Field(..., description="URL completa del proxy, ej. http://usuario:clave@ip:puerto")
    enabled: bool = True
    country: Optional[str] = "Germany"


@router.get("/bots-settings/proxy")
async def get_exchange_proxy():
    """Devuelve el estado del proxy saliente para exchanges configurado en la base de datos."""
    pool = await get_db_pool()
    async with pool.acquire() as conn:
        await _ensure_bot_tables(conn)
        row = await conn.fetchrow("SELECT value_json, updated_at FROM system_settings WHERE key = 'exchange_proxy';")
        if not row:
            return {"configured": False, "enabled": False, "proxy_url": None, "country": None}
        raw = row["value_json"]
        data = json.loads(raw) if isinstance(raw, str) else raw
        raw_url = data.get("proxy_url") or ""
        decrypted = decrypt_secret(raw_url) or raw_url
        
        # Enmascarar credenciales para la respuesta UI
        masked = None
        if decrypted and "@" in decrypted:
            proto, rest = decrypted.split("://", 1) if "://" in decrypted else ("http", decrypted)
            creds, host = rest.split("@", 1)
            masked = f"{proto}://***:***@{host}"
        elif decrypted:
            masked = decrypted

        return {
            "configured": bool(decrypted),
            "enabled": bool(data.get("enabled", True)),
            "masked_url": masked,
            "ip": data.get("ip"),
            "port": data.get("port"),
            "country": data.get("country", "Germany"),
            "updated_at": row["updated_at"]
        }


@router.put("/bots-settings/proxy")
async def update_exchange_proxy(req: UpdateExchangeProxyIn):
    """Guarda y encripta (AES-256) el proxy saliente para exchanges en la base de datos."""
    clean_url = req.proxy_url.strip()
    if req.enabled and not clean_url:
        raise HTTPException(status_code=400, detail="Debes proporcionar una URL válida de proxy (http://user:pass@ip:port).")

    pool = await get_db_pool()
    async with pool.acquire() as conn:
        await _ensure_bot_tables(conn)
        now_ms = int(time.time() * 1000)
        
        ip_extracted = None
        port_extracted = None
        if "@" in clean_url:
            host_part = clean_url.split("@")[-1]
            if ":" in host_part:
                ip_extracted, port_extracted = host_part.split(":", 1)
                port_extracted = int(port_extracted.split("/")[0]) if port_extracted else None

        payload = {
            "proxy_url": encrypt_secret(clean_url) if clean_url else "",
            "enabled": req.enabled,
            "ip": ip_extracted,
            "port": port_extracted,
            "country": req.country or "Germany",
            "updated_at": now_ms
        }
        await conn.execute("""
            INSERT INTO system_settings (key, value_json, updated_at)
            VALUES ('exchange_proxy', $1, $2)
            ON CONFLICT (key) DO UPDATE
            SET value_json = EXCLUDED.value_json,
                updated_at = EXCLUDED.updated_at;
        """, json.dumps(payload), now_ms)

        return {"success": True, "message": "Proxy guardado y cifrado en base de datos correctamente.", "enabled": req.enabled}


@router.post("/bots-settings/proxy/test")
async def test_exchange_proxy_connection(req: UpdateExchangeProxyIn):
    """Prueba la conectividad contra KuCoin a través del proxy proporcionado y mide latencia."""
    clean_url = req.proxy_url.strip()
    if not clean_url:
        pool = await get_db_pool()
        async with pool.acquire() as conn:
            row = await conn.fetchrow("SELECT value_json FROM system_settings WHERE key = 'exchange_proxy';")
            if row:
                data = json.loads(row["value_json"]) if isinstance(row["value_json"], str) else row["value_json"]
                clean_url = decrypt_secret(data.get("proxy_url", "")) or data.get("proxy_url", "")

    if not clean_url:
        raise HTTPException(status_code=400, detail="No hay proxy configurado para probar.")

    start_ts = time.time()
    ex = ccxt.kucoin({
        "enableRateLimit": True,
        "aiohttp_proxy": clean_url,
    })
    try:
        server_time = await ex.fetch_time()
        latency_ms = int((time.time() - start_ts) * 1000)
        return {
            "success": True,
            "latency_ms": latency_ms,
            "server_time": server_time,
            "message": f"Conexión exitosa con KuCoin a través del proxy ({latency_ms} ms)."
        }
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Fallo de conexión al proxy hacia KuCoin: {e}")
    finally:
        await ex.close()
