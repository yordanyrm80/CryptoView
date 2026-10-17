from fastapi import APIRouter, Depends, HTTPException, Query, Path
from typing import List, Dict, Any, Optional
from datetime import datetime
from pydantic import BaseModel, Field

from app.database import get_db_pool
from app.auth import verify_api_key
from app.services.crypto import encrypt_secret, decrypt_secret, mask_secret
import ccxt.async_support as ccxt

router = APIRouter(
    prefix="/api/v1/keys",
    tags=["Exchange API Keys"],
    dependencies=[Depends(verify_api_key)]
)

class ExchangeKeyIn(BaseModel):
    exchange: str = Field(..., description="Identificador del exchange en minúsculas (binance, kucoin, etc.)")
    api_key: str = Field(..., description="API Key pública/identificador provisto por el exchange")
    api_secret: str = Field(..., description="API Secret o clave secreta")
    api_passphrase: Optional[str] = Field("", description="Passphrase o contraseña de API (requerido por KuCoin)")
    is_active: bool = Field(True, description="Si las credenciales están activas para sincronización")

class ExchangeKeyOut(BaseModel):
    exchange: str
    api_key_masked: str
    has_passphrase: bool
    is_active: bool
    updated_at: datetime

@router.get("", response_model=List[ExchangeKeyOut])
async def list_exchange_keys():
    """
    Lista las claves de exchange configuradas en el servidor.
    Por seguridad, las claves secretas NUNCA son devueltas en texto plano.
    """
    pool = await get_db_pool()
    query = """
        SELECT exchange, api_key_encrypted, api_passphrase_encrypted, is_active, updated_at
        FROM api_keys
        ORDER BY exchange ASC;
    """
    async with pool.acquire() as conn:
        rows = await conn.fetch(query)

    result = []
    for r in rows:
        decrypted_key = decrypt_secret(r["api_key_encrypted"])
        has_pass = bool(r["api_passphrase_encrypted"] and len(r["api_passphrase_encrypted"].strip()) > 0)
        result.append(
            ExchangeKeyOut(
                exchange=r["exchange"],
                api_key_masked=mask_secret(decrypted_key),
                has_passphrase=has_pass,
                is_active=r["is_active"],
                updated_at=r["updated_at"]
            )
        )
    return result

@router.post("", status_code=201)
async def save_exchange_key(payload: ExchangeKeyIn):
    """
    Guarda o actualiza las credenciales de un exchange.
    Los datos se cifran con AES-256 usando la ENCRYPTION_KEY maestra antes de persistir en PostgreSQL.
    """
    exchange_name = payload.exchange.lower().strip()
    if not exchange_name:
        raise HTTPException(status_code=400, detail="El nombre del exchange no puede estar vacío.")

    enc_key = encrypt_secret(payload.api_key.strip())
    enc_secret = encrypt_secret(payload.api_secret.strip())
    enc_pass = encrypt_secret(payload.api_passphrase.strip()) if payload.api_passphrase else ""

    if not enc_key or not enc_secret:
        raise HTTPException(status_code=500, detail="Error en el cifrado de credenciales. Verifique ENCRYPTION_KEY.")

    pool = await get_db_pool()
    query = """
        INSERT INTO api_keys (exchange, api_key_encrypted, api_secret_encrypted, api_passphrase_encrypted, is_active, updated_at)
        VALUES ($1, $2, $3, $4, $5, NOW())
        ON CONFLICT (exchange)
        DO UPDATE SET
            api_key_encrypted = EXCLUDED.api_key_encrypted,
            api_secret_encrypted = EXCLUDED.api_secret_encrypted,
            api_passphrase_encrypted = EXCLUDED.api_passphrase_encrypted,
            is_active = EXCLUDED.is_active,
            updated_at = NOW()
        RETURNING exchange, is_active, updated_at;
    """

    async with pool.acquire() as conn:
        row = await conn.fetchrow(query, exchange_name, enc_key, enc_secret, enc_pass, payload.is_active)

    return {
        "status": "ok",
        "message": f"Credenciales de {exchange_name.upper()} almacenadas y cifradas exitosamente.",
        "exchange": row["exchange"],
        "is_active": row["is_active"],
        "updated_at": row["updated_at"]
    }

@router.delete("/{exchange}")
async def remove_exchange_key(
    exchange: str = Path(..., description="Nombre del exchange a eliminar o desactivar"),
    hard_delete: bool = Query(False, description="Si es True, elimina el registro por completo; si es False, solo lo desactiva")
):
    """
    Desactiva o elimina las credenciales del exchange especificado.
    """
    exchange_name = exchange.lower().strip()
    pool = await get_db_pool()

    async with pool.acquire() as conn:
        if hard_delete:
            res = await conn.execute("DELETE FROM api_keys WHERE exchange = $1;", exchange_name)
            if res == "DELETE 0":
                raise HTTPException(status_code=404, detail=f"No existen credenciales para {exchange_name}")
            return {"status": "ok", "message": f"Credenciales de {exchange_name.upper()} eliminadas definitivamente."}
        else:
            row = await conn.fetchrow("""
                UPDATE api_keys
                SET is_active = FALSE, updated_at = NOW()
                WHERE exchange = $1
                RETURNING exchange, is_active;
            """, exchange_name)
            if not row:
                raise HTTPException(status_code=404, detail=f"No existen credenciales para {exchange_name}")
            return {"status": "ok", "message": f"Credenciales de {exchange_name.upper()} desactivadas."}

@router.post("/{exchange}/test")
async def test_exchange_connection(
    exchange: str = Path(..., description="Nombre del exchange a verificar")
):
    """
    Prueba la validez de las credenciales almacenadas para un exchange realizando una llamada de solo lectura.
    """
    exchange_name = exchange.lower().strip()
    pool = await get_db_pool()

    query = """
        SELECT api_key_encrypted, api_secret_encrypted, api_passphrase_encrypted
        FROM api_keys
        WHERE exchange = $1 AND is_active = TRUE;
    """
    async with pool.acquire() as conn:
        row = await conn.fetchrow(query, exchange_name)

    if not row:
        raise HTTPException(status_code=404, detail=f"No hay credenciales activas registradas para '{exchange_name}'.")

    raw_key = decrypt_secret(row["api_key_encrypted"])
    raw_secret = decrypt_secret(row["api_secret_encrypted"])
    raw_pass = decrypt_secret(row["api_passphrase_encrypted"]) if row["api_passphrase_encrypted"] else ""

    if not hasattr(ccxt, exchange_name):
        raise HTTPException(status_code=400, detail=f"Exchange '{exchange_name}' no soportado por CCXT.")

    exchange_class = getattr(ccxt, exchange_name)
    config = {
        "apiKey": raw_key,
        "secret": raw_secret,
        "enableRateLimit": True,
    }
    if raw_pass:
        config["password"] = raw_pass

    client = exchange_class(config)
    try:
        # Llamada de lectura de balance spot para verificar las claves
        balance = await client.fetch_balance()
        # Contar monedas con balance mayor a cero
        total_assets = len([k for k, v in balance.get("total", {}).items() if v and v > 0])
        return {
            "status": "ok",
            "message": f"Conexión con {exchange_name.upper()} verificada exitosamente.",
            "assets_with_balance": total_assets
        }
    except Exception as e:
        return {
            "status": "error",
            "message": f"Error de autenticación con {exchange_name.upper()}: {str(e)}"
        }
    finally:
        await client.close()
