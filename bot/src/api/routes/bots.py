from typing import List
from fastapi import APIRouter, HTTPException, status
from src.api.schemas import (
    BotEventResponse,
    BotSummaryResponse,
    CapitalTransactionItemResponse,
    CapitalTransactionRequest,
    CapitalTransactionResponse,
    CreateBotRequest,
    PlateauStatusResponse,
    TrancheResponse,
)
from src.api.services.bot_service import BotService

router = APIRouter(prefix="/bots", tags=["Bots"])


@router.get("", response_model=List[BotSummaryResponse], summary="List all active bots")
def list_bots():
    service = BotService.get_instance()
    return service.list_bots()


@router.get("/{bot_id}", response_model=BotSummaryResponse, summary="Get bot details by ID")
def get_bot(bot_id: str):
    service = BotService.get_instance()
    bot = service.get_bot(bot_id)
    if not bot:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=f"Bot with ID '{bot_id}' not found.")
    return bot


@router.get("/{bot_id}/tranches", response_model=List[TrancheResponse], summary="List active and historical tranches")
def get_bot_tranches(bot_id: str):
    service = BotService.get_instance()
    tranches = service.get_bot_tranches(bot_id)
    if tranches is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=f"Bot with ID '{bot_id}' not found.")
    return tranches


@router.post("", response_model=BotSummaryResponse, status_code=status.HTTP_201_CREATED, summary="Create a new bot")
async def create_bot(req: CreateBotRequest):
    service = BotService.get_instance()
    try:
        return service.create_bot(req)
    except ValueError as e:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(e))


@router.post("/test", response_model=BotSummaryResponse, status_code=status.HTTP_201_CREATED, summary="Generate an instant test bot")
async def generate_test_bot(dry_run: bool = True, budget: float = 100.0):
    service = BotService.get_instance()
    try:
        return service.create_test_bot(dry_run=dry_run, budget=budget)
    except ValueError as e:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(e))


@router.post("/{bot_id}/start", summary="Start bot execution")
async def start_bot(bot_id: str):
    service = BotService.get_instance()
    try:
        success = service.resume_bot(bot_id)
    except ValueError as e:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(e))
    if not success:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=f"Bot with ID '{bot_id}' not found.")
    return {"message": f"Bot '{bot_id}' started successfully.", "status": "RUNNING"}


@router.post("/{bot_id}/stop", summary="Stop bot execution")
async def stop_bot(bot_id: str):
    service = BotService.get_instance()
    success = service.stop_bot(bot_id)
    if not success:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=f"Bot with ID '{bot_id}' not found.")
    return {"message": f"Bot '{bot_id}' stopped successfully.", "status": "STOPPED"}


@router.post("/{bot_id}/pause", summary="Pause bot execution")
async def pause_bot(bot_id: str):
    service = BotService.get_instance()
    success = service.pause_bot(bot_id)
    if not success:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=f"Bot with ID '{bot_id}' not found.")
    return {"message": f"Bot '{bot_id}' paused successfully.", "status": "PAUSED"}


@router.post("/{bot_id}/resume", summary="Resume bot execution")
async def resume_bot(bot_id: str):
    service = BotService.get_instance()
    try:
        success = service.resume_bot(bot_id)
    except ValueError as e:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(e))
    if not success:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=f"Bot with ID '{bot_id}' not found.")
    return {"message": f"Bot '{bot_id}' resumed successfully.", "status": "RUNNING"}


@router.post("/{bot_id}/withdraw", response_model=CapitalTransactionResponse, summary="Withdraw available cash from bot")
def withdraw_capital(bot_id: str, req: CapitalTransactionRequest):
    service = BotService.get_instance()
    try:
        return service.withdraw_capital(bot_id, req)
    except ValueError as e:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(e))


@router.post("/{bot_id}/deposit", response_model=CapitalTransactionResponse, summary="Deposit additional capital to bot")
def deposit_capital(bot_id: str, req: CapitalTransactionRequest):
    service = BotService.get_instance()
    try:
        return service.deposit_capital(bot_id, req)
    except ValueError as e:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(e))


@router.get("/{bot_id}/plateau-status", response_model=PlateauStatusResponse, summary="Assess plateau phase and capital readiness")
def get_plateau_status(bot_id: str):
    service = BotService.get_instance()
    diag = service.get_plateau_status(bot_id)
    if not diag:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=f"Bot with ID '{bot_id}' not found.")
    return diag


@router.get("/{bot_id}/transactions", response_model=List[CapitalTransactionItemResponse], summary="Capital deposits and withdrawals history")
def get_capital_transactions(bot_id: str):
    service = BotService.get_instance()
    bot = service.get_bot(bot_id)
    if not bot:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=f"Bot with ID '{bot_id}' not found.")
    return service.get_capital_transactions(bot_id)


@router.get("/{bot_id}/events", response_model=List[BotEventResponse], summary="Bot audit event history")
def get_bot_events(bot_id: str):
    service = BotService.get_instance()
    bot = service.get_bot(bot_id)
    if not bot:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=f"Bot with ID '{bot_id}' not found.")
    return service.get_bot_events(bot_id)


# Backward compatibility aliases
listar_bots = list_bots
obtener_bot = get_bot
obtener_tramos_bot = get_bot_tranches
crear_bot = create_bot
pausar_bot = pause_bot
reanudar_bot = resume_bot
retirar_capital = withdraw_capital
depositar_capital = deposit_capital
obtener_estado_meseta = get_plateau_status
obtener_transacciones_capital = get_capital_transactions
obtener_eventos_bot = get_bot_events

