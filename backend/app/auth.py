import secrets
from fastapi import Security, HTTPException, status
from fastapi.security import APIKeyHeader
from app.config import settings

api_key_header = APIKeyHeader(name="X-API-Key", auto_error=False)

async def verify_api_key(api_key: str = Security(api_key_header)) -> bool:
    """
    Verifica que la cabecera 'X-API-Key' coincida con API_SECRET_TOKEN configurado en el servidor (.env).
    Usa comparación en tiempo constante (secrets.compare_digest) para evitar ataques de canal lateral.
    """
    secret_token = settings.API_SECRET_TOKEN
    if not secret_token or not secret_token.strip():
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Error crítico de seguridad: API_SECRET_TOKEN no está configurado en el servidor.",
        )
    
    if not api_key or not secrets.compare_digest(api_key.strip(), secret_token.strip()):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Acceso denegado: Cabecera 'X-API-Key' ausente o token inválido.",
        )
    return True
