# CryptoView Data Engine & Central API

Backend de ingestión 24/7 y almacén histórico de series temporales financieras sobre **PostgreSQL 17 + TimescaleDB** con API privada en **FastAPI**.

---

## 🔐 Seguridad y Arquitectura Dinámica

1. **Claves de Exchange en Base de Datos Cifradas (AES-256)**:
   - Ya no necesitas editar `.env` ni reiniciar contenedores cuando quieras agregar o rotar API Keys de Binance, KuCoin, etc.
   - Las claves se envían a través de la API privada y se guardan cifradas en la tabla `api_keys` con la clave maestra `ENCRYPTION_KEY`.
   - Por seguridad, los endpoints de la API **nunca** exponen secretos en texto plano (se muestran enmascarados como `kuco...1234`).
2. **Símbolos Dinámicos**:
   - Los pares a monitorear se almacenan en `tracked_symbols` y se sincronizan en caliente sin reiniciar el worker.
3. **Autenticación Unificada**:
   - Todas las llamadas de administración (gestionar claves, añadir monedas, registrar operaciones) requieren la cabecera HTTP `X-API-Key: <TU_API_SECRET_TOKEN>`.

---

## 📍 Datos Exactos del Servidor de Producción (Oracle Cloud)

* **Proveedor / Región**: Oracle Cloud Infrastructure (`us-phoenix-1`)
* **Servidor (VM)**: `cryptoview-server` (`ubuntu@cryptoview-server`)
* **Ruta exacta de despliegue en el servidor**: `/home/ubuntu/backend` (`~/backend`)
  * Configuración: `/home/ubuntu/backend/.env`
  * Docker Compose: `/home/ubuntu/backend/docker-compose.yml`
  * SQL Init: `/home/ubuntu/backend/sql/01_init.sql`
  * Código fuente: `/home/ubuntu/backend/app/`
* **Ruta local en PC (Windows)**: `d:\Proyectos\Mios\CryptoView\backend`
* **Contenedores activos**:
  * `cryptoview-timescaledb` (`127.0.0.1:5432->5432`)
  * `cryptoview-api` (`0.0.0.0:8000->8000`)
  * `cryptoview-worker` (daemon 24/7)
* **Identificadores OCI (OCIDs)**:
  * **Instance OCID**: `ocid1.instance.oc1.phx.anyhqljrwg5llficuqkptjpizvcb3dtt7rp5f3tegxq6nme3nbqcvgdnkmxq`
  * **Subnet OCID**: `ocid1.subnet.oc1.phx.aaaaaaaaqiciizmn7bmvf2wooybnll5gyeqttgt3ae7zpwpqxchvl7banocq`
  * **Security List OCID**: `ocid1.securitylist.oc1.phx.aaaaaaaamlbc7s3qedul2h2qj77tuzzud3qytfrm44ffpxyzhuvw7psq5cja`

### ⚡ Comando directo para actualizar archivos desde Windows (sin duplicar carpetas):
```powershell
scp -r d:\Proyectos\Mios\CryptoView\backend\* d:\Proyectos\Mios\CryptoView\backend\.env ubuntu@TU_IP:/home/ubuntu/backend/
```

### ⚡ Comando directo en el servidor para aplicar cambios:
```bash
cd /home/ubuntu/backend && docker compose up -d --build
```

---

## 🚀 Despliegue Inicial desde Cero (Referencia)

### 1. Instalar Docker y Docker Compose en la máquina virtual
Conéctate por SSH a tu VM de Oracle Cloud y ejecuta:
```bash
sudo apt update && sudo apt upgrade -y
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER
```
*(Cierra y vuelve a abrir tu sesión SSH para aplicar los permisos de Docker)*.

---

### 2. Clonar o subir la carpeta `backend` a tu servidor
En tu servidor:
```bash
git clone <tu-repositorio>
cd CryptoView/backend
```
*(O copia directamente la carpeta `backend` mediante SCP / SFTP)*.

---

### 3. Configurar variables de entorno y levantar el stack
```bash
cp .env.example .env
# Opcional: edita tu API_SECRET_TOKEN y ENCRYPTION_KEY en .env con nano
nano .env

# Iniciar los servicios
docker compose up -d --build
```

---

## 🔍 Comandos útiles de gestión

* **Ver estado de los contenedores**:
  ```bash
  docker compose ps
  ```
* **Ver logs del colector 24/7 en tiempo real**:
  ```bash
  docker compose logs -f worker
  ```
* **Ver logs de la API**:
  ```bash
  docker compose logs -f api
  ```
* **Reiniciar todo**:
  ```bash
  docker compose restart
  ```

---

* **URL Base Segura (HTTPS)**: `https://129-146-110-196.sslip.io`
* **Diagnóstico / Salud**: `GET /api/v1/health` (`https://129-146-110-196.sslip.io/api/v1/health`)
* **Documentación Interactiva (Swagger UI)**: `https://129-146-110-196.sslip.io/docs`

### 🔑 Gestión de API Keys de Exchanges (`X-API-Key` requerido)

* **Listar exchanges configurados** (claves enmascaradas):
  ```bash
  curl -H "X-API-Key: cryptoview_secret_token_seguro_2026" \
       https://129-146-110-196.sslip.io/api/v1/keys
  ```

* **Guardar / Actualizar credenciales (se cifran automáticamente con AES-256)**:
  ```bash
  curl -X POST http://TU_IP:8000/api/v1/keys \
       -H "Content-Type: application/json" \
       -H "X-API-Key: cryptoview_secret_token_seguro_2026" \
       -d '{
         "exchange": "kucoin",
         "api_key": "tu_api_key_aqui",
         "api_secret": "tu_api_secret_aqui",
         "api_passphrase": "tu_passphrase_aqui",
         "is_active": true
       }'
  ```

* **Probar conexión con un exchange**:
  ```bash
  curl -X POST http://TU_IP:8000/api/v1/keys/kucoin/test \
       -H "X-API-Key: cryptoview_secret_token_seguro_2026"
  ```

* **Desactivar o eliminar credenciales**:
  ```bash
  curl -X DELETE "http://TU_IP:8000/api/v1/keys/kucoin?hard_delete=false" \
       -H "X-API-Key: cryptoview_secret_token_seguro_2026"
  ```

---

### 📊 Datos y Monedas

* **Velas históricas**:
  ```bash
  curl "http://TU_IP:8000/api/v1/candles?exchange=kucoin&symbol=BTC/USDT&interval=1h&limit=500"
  ```

* **Listar monedas en seguimiento**:
  ```bash
  curl http://TU_IP:8000/api/v1/symbols
  ```

* **Agregar nueva moneda al monitoreo 24/7**:
  ```bash
  curl -X POST http://TU_IP:8000/api/v1/symbols \
       -H "Content-Type: application/json" \
       -H "X-API-Key: cryptoview_secret_token_seguro_2026" \
       -d '{"exchange": "binance", "symbol": "ETH/USDT"}'
  ```
