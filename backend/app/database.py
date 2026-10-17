import asyncpg
from typing import Optional
from app.config import settings

_pool: Optional[asyncpg.Pool] = None

async def init_db_pool() -> asyncpg.Pool:
    global _pool
    if _pool is None:
        _pool = await asyncpg.create_pool(
            dsn=settings.DATABASE_URL,
            min_size=2,
            max_size=15,
            command_timeout=60,
        )
    return _pool

async def get_db_pool() -> asyncpg.Pool:
    global _pool
    if _pool is None:
        await init_db_pool()
    return _pool

async def close_db_pool():
    global _pool
    if _pool is not None:
        await _pool.close()
        _pool = None
