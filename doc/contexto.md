# Contexto del Proyecto: CryptoView (Clon de TabTrader)

Este archivo sirve como referencia de contexto rápido para las herramientas, la arquitectura, el entorno de desarrollo y la persistencia de datos.

---

## 1. Repositorio y Entorno de Desarrollo

* **Repositorio Oficial de GitHub**: `https://github.com/yordanyrm80/CryptoView.git`
* **SDK de Flutter & Dart**: Instalado y configurado en el `PATH` global del sistema.
* **Plataformas de Compilación Objetivo**: 
  * **Escritorio**: Windows (compilación nativa MSVC / C++ / FFI).
  * **Móvil**: Android (Emulador AVD `invera_phone` / Dispositivo Físico) e iOS.
* **Ruta de la Base de Datos SQLite en Windows Desktop**:
  `C:\Users\yordany\AppData\Roaming\com.yordany\cryptoview\CryptoView\cryptoview.db`
* **Ruta de la Base de Datos SQLite en Emulador Android**:
  `/data/data/com.cryptoview/databases/cryptoview.db` (en AVD: `invera_phone`)
* **Herramientas Android SDK**:
  `C:\Users\yordany\AppData\Local\Android\Sdk\platform-tools\adb.exe`

---

## 2. Arquitectura del Proyecto (Feature-First Modular)

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
```

---

## 3. Tecnologías y Librerías Core (Flutter)

1. **Gráficos Financieros Nativos**:
   * **Paquete**: `syncfusion_flutter_charts`.
   * **Implementación**: Velas japonesas (`CandleSeries`), líneas de soporte/resistencia y compras abiertas (`PlotBands`), regla de medición porcentual interactiva con área sombreada (`RangeAreaSeries`) y anotaciones de porcentaje/PnL (`CartesianChartAnnotation`). Soporte de drag & drop táctil/ratón para mover líneas sobre el gráfico.

2. **Base de Datos Local (SQLite)**:
   * **Paquetes**: `sqflite` (Android/iOS) + `sqflite_common_ffi` / `sqlite3_flutter_libs` (Windows Desktop).
   * **Estructura de Tablas**:
     * `transactions`: Compras y ventas con `exchange`, `symbol`, `type`, `price`, `amount`, `fee`, `date`, `is_matched`.
     * `matches`: Casamientos de operaciones con `buy_transaction_id`, `sell_transaction_id`, `matched_amount`, `profit`, `date`.
     * `drawings`: Líneas de soporte/resistencia (`price`, `color`, `label`, `exchange`, `symbol`).
     * `api_keys`: Credenciales API (`exchange`, `api_key`, `api_secret`, `api_passphrase`).
     * `api_sync`: Marcas de tiempo de última sincronización (`exchange`, `symbol`, `last_sync_date`).

3. **Conexión REST a Exchanges**:
   * **Paquetes**: `http` y `crypto` (HMAC SHA256).
   * **Exchanges Integrados**:
     * **KuCoin**: Klines públicos, tickers, balance de cuentas (`/api/v1/accounts`) y private fills (`/api/v1/fills`) con paginación iterativa en bloques de 7 días cubriendo hasta el límite máximo de retención API de 2 años (730 días) con barra de progreso en vivo.
     * **Binance**: Klines públicos, tickers, balance de cuentas (`/api/v3/account`) y private trades (`/api/v3/myTrades`) en bloques de 30 días hasta 2 años con progreso en vivo.
     * **BingX**: Klines públicos, tickers, balance spot (`/openApi/spot/v1/account/balance`) y private trades (`/openApi/spot/v1/trade/myTrades`) en bloques de 30 días hasta 2 años con progreso en vivo.

4. **Gestión de Estado**:
   * **Paquete**: `provider` (`WatchlistProvider`, `ChartProvider`, `TrackerProvider`).

---

## 4. Pruebas Realizadas y Datos de Referencia

* **Exchange Principal Probado**: **KuCoin**.
* **Par Principal de Pruebas**: **`ETH/USDT`** (en KuCoin API se formatea como `ETH-USDT`).
* **Operaciones reales sincronizadas**:
  * `BUY 0.2447831 ETH/USDT @ $1,633.55` (07-Jun-2026)
  * `SELL 0.24478 ETH/USDT @ $1,772.00` (17-Jun-2026)
  * `BUY 0.2302344 ETH/USDT @ $1,739.05` (22-Jun-2026)
  * `SELL 0.2302 ETH/USDT @ $1,876.12` (14-Jul-2026)
  * `SELL 0.1963 ETH/USDT @ $2,258.65` (19-Ago-2026)

---

## 5. Comandos Útiles de Consola (PowerShell / CMD)

* **Ejecutar en Windows Desktop**: `flutter run -d windows`
* **Lanzar Emulador Android**: `flutter emulators --launch invera_phone`
* **Ejecutar en Emulador Android**: `flutter run -d invera_phone`
* **Verificar dispositivos conectados**: `flutter devices`
* **Limpiar y regenerar paquetes**: `flutter clean && flutter pub get`
