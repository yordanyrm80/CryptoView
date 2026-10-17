from fastapi import FastAPI, Depends
from fastapi.middleware.cors import CORSMiddleware
from contextlib import asynccontextmanager

from app.database import init_db_pool, close_db_pool
from app.auth import verify_api_key
from app.routers import candles, trades, symbols, health, api_keys, backup

@asynccontextmanager
async def lifespan(app: FastAPI):
    # Inicio: inicializar pool de conexiones a PostgreSQL / TimescaleDB
    print("Iniciando conexión a base de datos PostgreSQL 17...")
    await init_db_pool()
    yield
    # Cierre: liberar conexiones
    print("Cerrando conexiones a base de datos...")
    await close_db_pool()

app = FastAPI(
    title="CryptoView Central Data Engine API",
    description="API privada de alta velocidad y almacén histórico 24/7 de velas y operaciones",
    version="1.0.0",
    lifespan=lifespan,
    dependencies=[Depends(verify_api_key)],
    docs_url=None,
    redoc_url=None,
    openapi_url=None,
)

# Permitir CORS seguro para CryptoView Desktop y navegadores
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["GET", "POST", "PUT", "DELETE", "OPTIONS"],
    allow_headers=["Content-Type", "X-API-Key", "Authorization"],
)

# Registrar Routers
app.include_router(health.router)
app.include_router(candles.router)
app.include_router(trades.router)
app.include_router(symbols.router)
app.include_router(api_keys.router)
app.include_router(backup.router)

@app.get("/")
async def root():
    return {
        "service": "CryptoView Data Engine & Warehouse",
        "version": "1.0.0",
        "docs": "/docs",
        "health": "/api/v1/health"
    }
