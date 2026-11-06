# CryptoView Data Engine & Central API 🚀

Backend de ingestión 24/7 y almacén histórico de series temporales financieras sobre **PostgreSQL 17 + TimescaleDB** con API privada en **FastAPI** y proxy inverso **Caddy (HTTPS)**.

---

## 🔐 Seguridad y Arquitectura

1. **Proxy Inverso Seguro (Caddy + HTTPS Automático)**:
   - Todo el tráfico externo viaja cifrado mediante TLS con certificado oficial de Let's Encrypt en `https://129-146-110-196.sslip.io`.
   - El puerto interno de la API (`8000`) está enlazado estrictamente a `127.0.0.1:8000`, impidiendo cualquier acceso no cifrado o directo desde Internet.
   - Cabeceras de seguridad activadas: HSTS, `X-Content-Type-Options: nosniff`, `X-Frame-Options: DENY`, `Referrer-Policy: no-referrer`.
   - Límite de carga de peticiones fijado en 50MB para respaldos.

2. **Mitigación contra Fuerza Bruta & Rate Limiting (`auth.py`)**:
   - **Comparación en Tiempo Constante**: Se emplea `secrets.compare_digest` para validar `X-API-Key` y prevenir ataques de temporización (timing attacks).
   - **Bloqueo por Fuerza Bruta**: Si una IP acumula 5 intentos fallidos consecutivos en 60 segundos, queda bloqueada temporalmente durante 5 minutos (`HTTP 429 Too Many Requests`).
   - **Auto-recuperación**: Si la petición suministra el token maestro de 256 bits legítimo, el bloqueo temporal se levanta automáticamente.
   - **Límite de Peticiones**: 180 req/minuto por IP para evitar saturación DoS.
   - **Documentación Pública Oculta**: `docs_url=None` y `openapi_url=None` para evitar escaneos automatizados.

3. **Cifrado Simétrico de Claves de Exchanges (AES-256 / Fernet)**:
   - Las claves de KuCoin, Binance, etc. se almacenan cifradas en la tabla `api_keys` con la clave maestra `ENCRYPTION_KEY`.
   - La API nunca devuelve los secretos en texto plano (se retornan enmascarados como `kuco...1234`).

4. **Monitoreo Continuo del Ingestion Worker (Heartbeat)**:
   - El worker 24/7 actualiza periódicamente la tabla `system_heartbeat` con su estado, monedas activas y backfill pendiente.

---

## 📍 Datos del Servidor de Producción (Oracle Cloud)

* **Proveedor / Región**: Oracle Cloud Infrastructure (`us-phoenix-1`)
* **Servidor (VM)**: `cryptoview-server` (`ubuntu@129.146.110.196`)
* **Llave Privada SSH**: `C:\Users\yordany\.ssh\ssh-key-cryptoview-server.key`
* **URL Oficial de la API**: `https://129-146-110-196.sslip.io`
* **Ruta de Despliegue en el Servidor**: `/home/ubuntu/backend` (`~/backend`)
* **Contenedores Activos**:
  * `cryptoview-caddy`: Proxy inverso HTTPS (`80:80`, `443:443`).
  * `cryptoview-api`: FastAPI / Uvicorn (`127.0.0.1:8000->8000`).
  * `cryptoview-worker`: Demonio recolector continuo 24/7 (velas 1m y backfill).
  * `cryptoview-bot-supervisor`: Supervisor y ejecutor de bots cuantitativos 24/7.
  * `cryptoview-timescaledb`: TimescaleDB / PostgreSQL 17 (`127.0.0.1:5432->5432`).

---

## ⚡ Comandos de Mantenimiento

### Actualizar código desde Windows:
```powershell
scp -i "C:\Users\yordany\.ssh\ssh-key-cryptoview-server.key" -r backend/app backend/Caddyfile backend/sql backend/docker-compose.yml ubuntu@129.146.110.196:/home/ubuntu/backend/
```

### Reconstruir y reiniciar servicios en el servidor:
```bash
ssh -i "C:\Users\yordany\.ssh\ssh-key-cryptoview-server.key" ubuntu@129.146.110.196 "cd /home/ubuntu/backend && docker compose build api worker bot-supervisor && docker compose up -d api worker bot-supervisor && docker exec cryptoview-caddy caddy reload --config /etc/caddy/Caddyfile"
```

### Ver logs en vivo:
```bash
# Ingestion Worker (recolección de velas y backfill)
docker logs -f cryptoview-worker

# Bot Supervisor (ejecución y evaluación de bots cuantitativos)
docker logs -f cryptoview-bot-supervisor
docker logs -f cryptoview-worker

# Servidor API
docker logs -f cryptoview-api

# Proxy Caddy (tráfico y certificados SSL)
docker logs -f cryptoview-caddy
```

---

## 📡 Referencia de Endpoints Principales

> **Nota**: Todas las peticiones deben incluir la cabecera:  
> `X-API-Key: <API_SECRET_TOKEN>`

### 1. Diagnóstico y Salud del Sistema
* **`GET /api/v1/health`**:
  Devuelve el estado general del backend, conexión a base de datos, total de velas, símbolos en seguimiento y el estado en vivo del Ingestion Worker.
  ```json
  {
    "status": "online",
    "database": "connected (TimescaleDB / PostgreSQL 17)",
    "worker_status": "online",
    "worker_last_seen_seconds": 6.9,
    "worker_details": {
      "timestamp_utc": "2026-10-17T21:03:20Z",
      "active_symbols": 1,
      "pending_backfill": 1
    },
    "tracked_symbols_active": 1,
    "total_candles_stored": 4331482,
    "total_trades_stored": 0
  }
  ```

### 2. Velas y Precios de Mercado
* **`GET /api/v1/candles`**:
  Obtiene velas en orden cronológico ascendente. Cuenta con **enrutamiento jerárquico optimizado**:
  - `1m`, `3m`, `5m`: consulta la Hypertable `market_candles` o `candles_5m`.
  - `15m`, `30m`: consulta la Continuous Aggregate `candles_5m` (5x más rápido).
  - `1h`, `2h`, `4h`, `6h`, `12h`, `1d`, `1w`: consulta `candles_1h` (hasta 60x más rápido).
  *Parámetros:* `exchange`, `symbol`, `interval`, `limit`, `auto_track`, `end_time`.
* **`GET /api/v1/candles/tickers`**:
  Devuelve los últimos precios de mercado (`last_price`, `time`) de todos los pares en seguimiento.

### 3. Sincronización y Registro de Operaciones (Trades)
* **`POST /api/v1/trades/sync`**:
  Sincroniza órdenes directamente en el servidor conectándose al exchange con las credenciales descifradas (sin enviar secretos al cliente).
  *Parámetros:* `exchange`, `symbol` (opcional), `days` (por defecto 1).
* **`POST /api/v1/trades/batch`**:
  Inserta lotes de transacciones masivas saltando duplicados existentes (`ON CONFLICT (exchange, trade_id) DO NOTHING`).
* **`GET /api/v1/trades`**:
  Consulta el historial de órdenes guardadas en la base de datos central.
* **`PUT /api/v1/trades/{trade_id}` & `DELETE /api/v1/trades/{trade_id}`**:
  Edición de notas/remanente y borrado de operaciones.

### 4. Retiros y Casamientos
* **`POST /api/v1/withdrawals/sync`**:
  Descarga y almacena retiros/gastos del exchange en la tabla `account_withdrawals`.
* **`GET /api/v1/matches`**:
  Consulta los casamientos de compra/venta y cálculo de ganancias cerradas.

### 5. Respaldo Integral y Restauración (Arquitectura Dual)
* **A. Salva Ligera de Cuenta & Operaciones (`.json.gz`)**:
  - `GET /api/v1/backup/export?include_candles=false`:
    Genera un volcado atómico rápido (~1 segundo, <1 MB) con transacciones, retiros, casamientos, claves API cifradas y configuración de símbolos.
  - `POST /api/v1/backup/restore`:
    Restaura atómicamente el estado de la cuenta a partir del archivo `.json.gz` subido.
* **B. Salva Completa con Velas de Mercado (`.sql.gz` nativo TimescaleDB)**:
  - `POST /api/v1/backup/pg_dump/create`:
    Inicia un volcado nativo en segundo plano mediante `pg_dump | gzip` comprimido al vuelo en el volumen seguro `backups_data`. Respalda el 100% de la base de datos (más de 7.67 millones de velas, hypertables y continuous aggregates).
  - `GET /api/v1/backup/pg_dump/status`:
    Monitorea el progreso del volcado en background (`idle`, `in_progress`, `completed`, `error`), devolviendo tamaño en bytes y duración.
  - `GET /api/v1/backup/pg_dump/download/{filename}`:
    Transfiere el archivo comprimido `.sql.gz` en streaming de alta velocidad mediante chunks de 64KB sin saturar la memoria RAM.
  - `DELETE /api/v1/backup/pg_dump/{filename}`:
    Elimina volcados antiguos del disco del servidor para preservar almacenamiento.

#### 🔧 Restauración Manual del Volcado SQL Completo en Servidor VPS:
```bash
# Restaurar un volcado nativo .sql.gz en TimescaleDB (desde la carpeta ~/backups del VPS):
gunzip -c /home/ubuntu/backups/cryptoview_timescaledb_full_YYYY-MM-DD.sql.gz | docker compose -f /home/ubuntu/backend/docker-compose.yml exec -T timescaledb psql -U cryptoview -d cryptoview_db
```

### 6. Gestión de Credenciales y Monedas
* **`GET /api/v1/keys`**, **`POST /api/v1/keys`**, **`DELETE /api/v1/keys/{exchange}`**:
  Gestión segura de credenciales de exchanges cifradas con AES-256.
* **`GET /api/v1/symbols`**, **`POST /api/v1/symbols`**, **`DELETE /api/v1/symbols`**:
  Administración dinámica de monedas en seguimiento 24/7.

### 7. Gestión Unificada de Flota de Bots Cuantitativos (`routers/bots.py`)
* **`GET /api/v1/bots/metrics/overview`**:
  Métricas consolidadas de toda la flota (patrimonio en bots, liquidez libre, beneficio realizado neto, win rate).
* **`GET /api/v1/bots`**:
  Listado completo de bots registrados en PostgreSQL con sus tramos activos, capital disponible y alertas de liquidez.
* **`GET /api/v1/bots/{bot_id}/tranches`**:
  Escalera de tramos abiertos y cerrados de un bot específico.
* **`POST /api/v1/bots`**:
  Registra una nueva instancia de bot cuantitativo en la base de datos central.
* **`POST /api/v1/bots/{bot_id}/start|pause|resume|stop`**:
  Transiciones de estado operativas sincronizadas vía PostgreSQL con el ejecutor de bots.
* **`POST /api/v1/bots/{bot_id}/deposit|withdraw`**:
  Inyección o retiro de liquidez auditado en la tabla `capital_transactions`.
* **`GET / PUT /api/v1/bots/settings/notifications`**:
  Configuración centralizada de alertas operativas por Webhook.

