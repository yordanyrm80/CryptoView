from typing import List
from fastapi import APIRouter
from src.api.schemas import EquityPointResponse, MetricsOverviewResponse
from src.api.services.bot_service import BotService

router = APIRouter(prefix="/metrics", tags=["Metrics"])


@router.get("/overview", response_model=MetricsOverviewResponse, summary="Portfolio overview metrics")
def get_portfolio_overview():
    service = BotService.get_instance()
    return service.get_portfolio_overview()


@router.get("/history", response_model=List[EquityPointResponse], summary="Equity history data points")
def get_equity_history():
    # Returns equity and cash flow data points for frontend charts (e.g. fl_chart)
    return [
        EquityPointResponse(timestamp=1700000000000, equity=10000.0, cash_flow=0.0),
        EquityPointResponse(timestamp=1710000000000, equity=11500.0, cash_flow=1200.0),
        EquityPointResponse(timestamp=1720000000000, equity=14400.0, cash_flow=4800.0),
    ]
