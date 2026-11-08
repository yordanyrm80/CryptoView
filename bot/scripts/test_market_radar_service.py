import asyncio
import os
import sys
from pathlib import Path

# Add backend and bot to path
backend_path = str(Path(__file__).resolve().parent.parent.parent / "backend")
sys.path.insert(0, backend_path)

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

import asyncpg
import json
from app.services.market_radar import MarketCycleRadarService

async def main():
    pool = await asyncpg.create_pool(
        host="127.0.0.1",
        port=5432,
        user="postgres",
        password="postgres",
        database="CryptoViewPruebas",
        min_size=1,
        max_size=3
    )
    
    print("Probando MarketCycleRadarService.analyze_market_cycle para BTC/USDT...")
    result = await MarketCycleRadarService.analyze_market_cycle(pool, "BTC/USDT")
    print(json.dumps(result, indent=2, ensure_ascii=False))
    
    await pool.close()

if __name__ == "__main__":
    asyncio.run(main())
