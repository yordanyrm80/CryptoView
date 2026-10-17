from pydantic_settings import BaseSettings

class Settings(BaseSettings):
    POSTGRES_USER: str = "cryptoview"
    POSTGRES_PASSWORD: str = "cryptoview_secure_pwd"
    POSTGRES_DB: str = "cryptoview_db"
    DATABASE_URL: str = "postgresql://cryptoview:cryptoview_secure_pwd@timescaledb:5432/cryptoview_db"

    # Tiempo de reposo del colector entre ciclos (en segundos)
    COLLECTOR_SLEEP_SECONDS: int = 20

    # Token para autorizar llamadas a la API (cabecera 'X-API-Key')
    API_SECRET_TOKEN: str = "cryptoview_secret_default"

    # Clave maestra de cifrado AES-256 para credenciales de exchanges en la BD
    ENCRYPTION_KEY: str = "cryptoview_master_aes_encryption_key_2026_super_secure!"

    class Config:
        env_file = ".env"
        extra = "ignore"

settings = Settings()
