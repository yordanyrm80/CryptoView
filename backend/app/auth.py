from fastapi import Security, HTTPException, status
from fastapi.security import APIKeyHeader
from app.config import settings

api_key_header = APIKeyHeader(name="X-API-Key", auto_error=False)

async def verify_api_key(api_key: str = Security(api_key_header)) -> bool:
    """
    Verifica que la cabecera 'X-API-Key' coincida con API_SECRET_TOKEN configurado en el servidor (.env).
    """
    if not settings.API_SECRET_TOKEN:
        return True
    
    if not api_key or api_key.strip() != settings.API_SECRET_TOKEN.strip():
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Autenticación requerida: Proporcione un token válido en la cabecera 'X-API-Key'.",
        )
    return True
