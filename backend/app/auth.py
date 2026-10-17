import time
import secrets
from collections import defaultdict
from fastapi import Request, Security, HTTPException, status
from fastapi.security import APIKeyHeader
from app.config import settings

api_key_header = APIKeyHeader(name="X-API-Key", auto_error=False)

# Rate limiting y mitigación contra fuerza bruta en memoria
_failed_attempts: dict[str, list[float]] = defaultdict(list)
_blocked_ips: dict[str, float] = {}
_request_history: dict[str, list[float]] = defaultdict(list)

MAX_FAILED_ATTEMPTS = 5
LOCKOUT_TIME_SECONDS = 300       # 5 minutos de bloqueo tras 5 fallos consecutivos
MAX_REQUESTS_PER_MINUTE = 180    # Límite general por IP (3 req/s sostenido)

def _get_client_ip(request: Request) -> str:
    forwarded_for = request.headers.get("x-forwarded-for")
    if forwarded_for:
        return forwarded_for.split(",")[0].strip()
    real_ip = request.headers.get("x-real-ip")
    if real_ip:
        return real_ip.strip()
    return request.client.host if request.client else "127.0.0.1"

async def verify_api_key(request: Request, api_key: str = Security(api_key_header)) -> bool:
    """
    Verifica que la cabecera 'X-API-Key' coincida con API_SECRET_TOKEN (.env).
    Incluye:
    1. Comparación en tiempo constante (secrets.compare_digest) contra timing attacks.
    2. Rate limiting general (180 peticiones/min) por IP para prevenir abusos y flooding.
    3. Bloqueo temporal (5 min) si se fallan 5 intentos consecutivos.
    4. Auto-recuperación si el cliente suministra el token maestro auténtico de 256 bits.
    """
    now = time.time()
    client_ip = _get_client_ip(request)

    # 1. Rate Limiting general por IP (ventana deslizante de 60 segundos)
    recent_requests = [t for t in _request_history[client_ip] if now - t < 60]
    if len(recent_requests) >= MAX_REQUESTS_PER_MINUTE:
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail="Tasa de peticiones excedida (máx 180 req/min). Reduzca la frecuencia.",
        )
    recent_requests.append(now)
    _request_history[client_ip] = recent_requests

    # 2. Validación del Secret Token del Servidor
    secret_token = settings.API_SECRET_TOKEN
    if not secret_token or not secret_token.strip():
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Error crítico de seguridad: API_SECRET_TOKEN no está configurado en el servidor.",
        )

    # 3. Comprobación del API Key suministrado en tiempo constante
    is_valid = bool(api_key and secrets.compare_digest(api_key.strip(), secret_token.strip()))

    if is_valid:
        # Si la IP tenía bloqueos o fallos previos y presentó la clave auténtica, se restablece
        _blocked_ips.pop(client_ip, None)
        _failed_attempts.pop(client_ip, None)
        return True

    # 4. Si la clave es inválida, evaluar bloqueo por fuerza bruta
    if client_ip in _blocked_ips:
        blocked_until = _blocked_ips[client_ip]
        if now < blocked_until:
            remaining = int(blocked_until - now)
            raise HTTPException(
                status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                detail=f"IP bloqueada temporalmente por intentos fallidos de autenticación. Intente de nuevo en {remaining}s.",
            )
        else:
            del _blocked_ips[client_ip]
            _failed_attempts[client_ip] = []

    # Registrar intento fallido
    recent_fails = [t for t in _failed_attempts[client_ip] if now - t < 60]
    recent_fails.append(now)
    _failed_attempts[client_ip] = recent_fails

    if len(recent_fails) >= MAX_FAILED_ATTEMPTS:
        _blocked_ips[client_ip] = now + LOCKOUT_TIME_SECONDS
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail=f"Demasiados intentos fallidos. IP bloqueada por {LOCKOUT_TIME_SECONDS // 60} minutos.",
        )

    raise HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Acceso denegado: Cabecera 'X-API-Key' ausente o token inválido.",
    )
