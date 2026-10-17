import base64
import hashlib
from typing import Optional
from cryptography.fernet import Fernet, InvalidToken
from app.config import settings

def _get_fernet() -> Fernet:
    """
    Deriva una clave simétrica Fernet de 32 bytes a partir de ENCRYPTION_KEY usando SHA-256.
    Permite usar cualquier frase de paso en el .env sin requerir formato estricto base64.
    """
    key_bytes = hashlib.sha256(settings.ENCRYPTION_KEY.encode('utf-8')).digest()
    fernet_key = base64.urlsafe_b64encode(key_bytes)
    return Fernet(fernet_key)

def encrypt_secret(plain_text: Optional[str]) -> str:
    """Cifra un texto plano usando AES-128-CBC/HMAC (Fernet) y devuelve una cadena de texto."""
    if not plain_text:
        return ""
    try:
        f = _get_fernet()
        encrypted_bytes = f.encrypt(plain_text.encode('utf-8'))
        return encrypted_bytes.decode('utf-8')
    except Exception as e:
        print(f"[Crypto Error] Error al cifrar: {e}")
        return ""

def decrypt_secret(cipher_text: Optional[str]) -> str:
    """Descifra una cadena previamente cifrada con Fernet. Si falla o es inválida, retorna vacío."""
    if not cipher_text:
        return ""
    try:
        f = _get_fernet()
        decrypted_bytes = f.decrypt(cipher_text.encode('utf-8'))
        return decrypted_bytes.decode('utf-8')
    except InvalidToken:
        print("[Crypto Error] Token o clave de descifrado inválida. ¿Cambió ENCRYPTION_KEY?")
        return ""
    except Exception as e:
        print(f"[Crypto Error] Error al descifrar: {e}")
        return ""

def mask_secret(secret: Optional[str]) -> str:
    """Oculta la mayoría de los caracteres para visualización segura en interfaces de usuario."""
    if not secret:
        return ""
    s = secret.strip()
    if len(s) <= 6:
        return "***"
    return f"{s[:4]}...{s[-4:]}"
