from fastapi import APIRouter, Query, Depends, HTTPException
from typing import Dict, Any
from app.database import get_db_pool
from app.auth import verify_api_key
from app.services.market_radar import MarketCycleRadarService

router = APIRouter(
    prefix="/api/v1/market-radar",
    tags=["Market Radar"],
    dependencies=[Depends(verify_api_key)]
)

@router.get("", response_model=Dict[str, Any], summary="Consultar Radar Macro de Bitcoin (BTC/USDT)")
async def get_default_market_radar():
    """
    Devuelve el estado del Radar de Ciclo Macro para BTC/USDT:
    - Señal de entrada (Ventana Dorada, Pozo de Capitulación, Halving Squeeze, Zona Roja).
    - Señal de salida / techo (Pi Cycle Top, Ruptura Estructural, Extensión Parabólica).
    100% consultivo e informativo: no bloquea ninguna operativa.
    """
    pool = await get_db_pool()
    result = await MarketCycleRadarService.analyze_market_cycle(pool, "BTC/USDT")
    if "error" in result:
        raise HTTPException(status_code=404, detail=result["error"])
    return result

@router.get("/{symbol:path}", response_model=Dict[str, Any], summary="Consultar Radar Macro por Símbolo")
async def get_symbol_market_radar(symbol: str):
    """
    Devuelve el estado del Radar de Ciclo Macro para cualquier símbolo con histórico (ej. BTC/USDT, ETH/USDT).
    """
    pool = await get_db_pool()
    result = await MarketCycleRadarService.analyze_market_cycle(pool, symbol)
    if "error" in result:
        raise HTTPException(status_code=404, detail=result["error"])
    return result
