from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from contextlib import asynccontextmanager

from app.database import init_db_pool, close_db_pool
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
)

# Permitir CORS para cualquier cliente (CryptoView Desktop, web, bots)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
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
