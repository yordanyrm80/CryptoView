# Arquitectura de CryptoView

Este documento describe la estructura de directorios, capas arquitectónicas y principios de diseño aplicados en **CryptoView**.

---

## 🏛️ Estructura de Directorios

El proyecto sigue una arquitectura modular orientada a funcionalidades (**Feature-First**) combinada con separación de responsabilidades:

```
lib/
├── core/                           # Recursos globales y utilidades independientes de features
│   ├── database/                   # Manejo de persistencia local (SQLite cross-platform)
│   │   └── database_helper.dart
│   ├── services/                   # Servicios de red, integración con APIs externas
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
│   │   ├── presentation/
│   │   │   ├── widgets/            # Widgets reutilizables de Watchlist
│   │   │   └── watchlist_screen.dart
│   │   └── providers/              # Gestor de estado de Watchlist
│   │
│   ├── chart/                      # 2. Gráficos interactivos de Trading
│   │   ├── domain/models/          # Modelos de velas, líneas y herramientas
│   │   ├── presentation/
│   │   │   ├── widgets/            # Barras de temporalidad, diálogos, insignias
│   │   │   └── chart_screen.dart   # Vista principal del gráfico SfCartesianChart
│   │   └── providers/              # Gestor de estado del gráfico y herramientas
│   │
│   └── tracker/                    # 3. Diario de trading y motor de casamiento
│       ├── domain/                 # Modelos de transacciones y casamientos (PnL)
│       │   ├── match_model.dart
│       │   └── transaction_model.dart
│       ├── presentation/
│       │   ├── widgets/            # Diálogos, modales, tarjetas y hojas de detalle
│       │   └── tracker_screen.dart # Pantalla principal del diario (3 pestañas)
│       └── providers/              # Gestor de estado del tracker y lógica de casamiento
│
└── main.dart                       # Inicialización, MultiProvider y Scaffold responsivo

backend/                            # Motor Central de Ingestión 24/7 y API (Desplegado en /home/ubuntu/backend)
├── app/
│   ├── routers/                    # Endpoints FastAPI (candles, trades, symbols, api_keys, health)
│   ├── services/                   # Colector 1m (collector.py), CCXT (exchange_client.py), Cifrado AES-256 (crypto.py)
│   ├── auth.py                     # Validación de cabecera X-API-Key
│   ├── config.py                   # Configuración Pydantic Settings
│   ├── database.py                 # Pool de conexiones asyncpg
│   └── main.py                     # Punto de entrada FastAPI
├── sql/
│   └── 01_init.sql                 # Esquema PostgreSQL 17 + TimescaleDB (Hypertable 1m + Continuous Aggregates)
├── Dockerfile                      # Imagen Python 3.12-slim compatible con ARM64
└── docker-compose.yml              # Stack (timescaledb, api, worker)
```

---

## ⚙️ Principios de Diseño

1. **Responsabilidad Única (SRP):** Cada archivo tiene un propósito claro y no sobrepasa las 150–250 líneas.
2. **Desacoplamiento de Widgets:** Los diálogos, modales y tarjetas complejas se extraen a archivos independientes dentro de `features/<feature>/presentation/widgets/`.
3. **Diseño Visual Centralizado:** Todos los colores provienen de `AppColors` para garantizar coherencia estética y facilitar el mantenimiento.
4. **Patrón Fachada para Exchanges:** `ExchangeService` expone métodos simplificados mientras delega internamente a las implementaciones especializadas de `BinanceService`, `KucoinService` y `BingxService`.
