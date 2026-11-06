# Arquitectura de CryptoView 🏛️

Este documento describe la estructura de directorios, capas arquitectónicas y principios de diseño aplicados en **CryptoView**.

---

## 🏗️ Estructura de Directorios

El proyecto sigue una arquitectura modular orientada a funcionalidades (**Feature-First**) combinada con un backend centralizado para series temporales:

```
lib/
├── core/                           # Recursos globales y utilidades independientes de features
│   ├── database/                   # Manejo de persistencia local (SQLite cross-platform)
│   │   └── database_helper.dart
│   ├── services/                   # Servicios de red e integraciones
│   │   ├── cloud_api_service.dart  # Cliente centralizado hacia el backend (con checkHealth)
│   │   └── exchanges/              # Conectores modulares por Exchange
│   │       ├── binance_service.dart
│   │       ├── kucoin_service.dart
│   │       ├── bingx_service.dart
│   │       └── exchange_service.dart # Fachada unificada
│   └── theme/                      # Sistema de diseño, tokens de color y tema global
│       ├── app_colors.dart
│       └── app_theme.dart
│
├── features/                       # Módulos funcionales de la aplicación
│   ├── watchlist/                  # 1. Seguimiento de pares y precios
│   │   ├── presentation/           # Widgets reutilizables y pantalla principal
│   │   └── providers/              # Gestor de estado de Watchlist
│   │
│   ├── chart/                      # 2. Gráficos interactivos de Trading
│   │   ├── domain/models/          # Modelos de velas, líneas y herramientas
│   │   ├── presentation/           # Pantalla SfCartesianChart y barras de temporalidad
│   │   └── providers/              # Gestor de estado del gráfico y herramientas
│   │
│   ├── tracker/                    # 3. Diario de trading y motor de casamiento
│   │   ├── domain/                 # Modelos de transacciones y casamientos (PnL)
│   │   ├── presentation/           # Pantalla principal del diario (3 pestañas)
│   │   └── providers/              # Gestor de estado del tracker y casamientos
│   │
│   ├── exchanges/                  # 4. Gestión de Exchanges y API Keys
│   │   └── presentation/           # Configuración de claves, saldo y sincronizaciones
│   │
│   ├── bots/                       # 5. Centro de Mando de Flota de Bots Cuantitativos
│   │   ├── domain/                 # Modelos ResumenBot, TramoBot, MetricasFlotaBots
│   │   ├── presentation/           # BotsWorkspaceScreen (KPIs, escalera de tramos, despliegue)
│   │   └── providers/              # BotsProvider (delega el 100% de red a CloudApiService)
│   │
│   └── settings/                   # 6. Ajustes y conexión Cloud
│       ├── presentation/           # Pantalla de ajustes y CloudServerConfigSection
│       └── providers/              # SettingsProvider (persistencia y migración de URL)
│
└── main.dart                       # Inicialización, MultiProvider y Scaffold responsivo (Activity Dock)

backend/                            # Motor Central de Ingestión 24/7 y API Única (/home/ubuntu/backend)
├── app/
│   ├── routers/                    # Endpoints FastAPI:
│   │   ├── candles.py              # Velas con enrutamiento jerárquico optimizado y tickers
│   │   ├── trades.py               # Sincronización en servidor, lotes y CRUD de órdenes
│   │   ├── symbols.py              # Gestión dinámica de pares monitoreados
│   │   ├── api_keys.py             # Claves de exchanges cifradas con AES-256
│   │   ├── health.py               # Diagnóstico de base de datos y latido del worker
│   │   ├── withdrawals.py          # Sincronización de retiros y gastos
│   │   ├── matches.py              # Casamientos de operaciones compra/venta
│   │   ├── backup.py               # Salva Ligera (.json.gz) y volcado nativo TimescaleDB (pg_dump / .sql.gz)
│   │   └── bots.py                 # Gestión unificada de flota de bots (/api/v1/bots, métricas, tramos y capital)
│   ├── services/
│   │   ├── collector.py            # Colector 24/7 (tiempo real + backfill + auto-sync trades)
│   │   ├── exchange_client.py      # Cliente unificado CCXT con descifrado AES en caliente
│   │   └── crypto.py               # Cifrado simétrico AES-256 (Fernet)
│   ├── auth.py                     # Validación X-API-Key, rate limiting (180/min) y bloqueo por fuerza bruta
│   ├── config.py                   # Configuración Pydantic Settings
│   ├── database.py                 # Pool asíncrono asyncpg
│   └── main.py                     # Punto de entrada FastAPI con dependencias globales
├── sql/
│   └── 01_init.sql                 # Esquema TimescaleDB: market_candles, continuous aggregates, heartbeat e índices
├── Caddyfile                       # Proxy inverso HTTPS automático (Let's Encrypt), headers de seguridad
├── Dockerfile                      # Imagen Python 3.12-slim compatible con ARM64
└── docker-compose.yml              # Orquestación de 4 contenedores (caddy, api, worker, timescaledb)

bot/                                # CriptoBot: Motor de Trading Cuantitativo Institucional
├── src/
│   ├── data_provider/              # Ingestión desacoplada (TimescaleMarketDataProvider vs ApiMarketDataProvider)
│   ├── strategies/                 # Estrategias (Quantum Compound, Evolution, Adaptive Three-Regime)
│   ├── core/                       # Ejecutor en vivo y detector de régimen de mercado
│   ├── domain/                     # Modelos de dominio canónicos (BotConfig, Tranche, Order, Candle)
│   ├── exchange/                   # Conector CCXT KuCoin Spot (ejecución y balance de subcuenta aislada)
│   ├── storage/                    # Repositorios PostgreSQL / auditoría de capital inmutable
│   └── api/                        # API FastAPI de control y canal WebSocket
├── criptobot_ui/                   # UI Flutter móvil/escritorio para control y telemetría
├── docs/                           # Manual Operativo Híbrido y bitácoras
└── tests/                          # Suite de pruebas automatizadas pytest (43 tests pasando)
```

---

## ⚙️ Principios de Diseño y Arquitectura

1. **Modelo Híbrido Offline-First con Nube Complementaria**:
   - El cliente local opera de forma completamente autónoma con **SQLite**: si no hay conexión a Internet o el servidor está en mantenimiento, la interfaz sigue abriendo gráficos cacheados, registrando operaciones y calculando PnL.
   - Cuando hay conexión, se conecta mediante HTTPS con el **Data Engine en Oracle Cloud**, beneficiándose de recolección continua de velas 1m sin tener la app abierta.

2. **Enrutamiento Jerárquico de Consultas de Velas**:
   - En lugar de escanear millones de registros en la Hypertable base `market_candles`, la API enruta dinámicamente:
     - `15m` y `30m` se calculan a partir de la Continuous Aggregate `candles_5m` (5x más veloz).
     - `1h` a `1d` se calculan a partir de `candles_1h` (hasta 60x más veloz).

3. **Centralización Segura de Sincronización de Operaciones**:
   - `POST /api/v1/trades/sync` permite que el servidor descargue las órdenes del exchange conectándose directamente a la API de KuCoin/Binance/BingX con las credenciales descifradas en memoria.
   - Esto evita que el cliente de escritorio maneje peticiones pesadas o exponga secretos a redes locales inseguras.

4. **Defensa en Profundidad (Seguridad Multicapa)**:
   - **Caddy**: Todo el tráfico entrante pasa por HTTPS en los puertos 80/443. Puerto 8000 expuesto únicamente en `127.0.0.1`.
   - **FastAPI**: Validación por `X-API-Key` con comparación en tiempo constante (`secrets.compare_digest`) para mitigar timing attacks.
   - **Anti-Brute Force**: Si una IP falla 5 veces en 60s, se bloquea por 5 minutos (`HTTP 429`), con desbloqueo inmediato si presenta la clave legítima.
   - **Rate Limiting**: Ventana deslizante de 180 peticiones por minuto por IP.
   - **AES-256**: Claves de exchanges nunca se almacenan en texto plano en la base de datos ni se exponen en endpoints de lectura.

5. **Monitoreo Reactivo de Latido (Worker Heartbeat)**:
   - El Ingestion Worker reporta su actividad periódicamente en `system_heartbeat`.
   - `/api/v1/health` inspecciona este registro para devolver si el worker está `online` (<90s) o `stalled`, permitiendo diagnósticos inmediatos desde la app o scripts externos.

6. **Desacoplamiento de Datos en CriptoBot (`MarketDataProvider`)**:
   - El bot cuantitativo no consulta a exchanges externos para velas OHLCV. En su lugar, utiliza el patrón abstracto `MarketDataProvider` configurable por la variable de entorno `DATA_SOURCE_MODE`:
     - **`database`**: Consultas directas SQL a TimescaleDB (`candles_1h`, `candles_5m`, `candles_1d`, `market_candles`) con latencia `< 1ms`, ideal cuando el bot corre co-ubicado en el servidor central.
     - **`api`**: Consultas remotas HTTPS a la API de CryptoView (`CryptoViewClient` con cabecera `X-API-Key`), ideal cuando el bot corre en un VPS independiente (como Tokio) o en local.
   - La librería CCXT se reserva exclusivamente para trading spot y balances en subcuentas de KuCoin.

7. **Arquitectura de Respaldo Dual y Continuidad de Negocio**:
   - **Salva Ligera de Cuenta & Trades (`.json.gz`)**: Diseñada para la app móvil y de escritorio; genera y restaura atómicamente el estado contable en ~1 segundo (<1 MB).
   - **Salva Completa con Series Temporales (`.sql.gz`)**: Diseñada para la base de datos central en producción; utiliza `pg_dump | gzip` en background para respaldar más de 7.67 millones de velas sin bloquear lecturas ni agotar la memoria, descargable en streaming y restaurable con comandos nativos de PostgreSQL.
