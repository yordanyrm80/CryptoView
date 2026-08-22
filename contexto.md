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

## 2. Tecnologías y Librerías Core (Flutter)

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
     * **KuCoin**: Klines públicos, tickers y private endpoint `/api/v1/fills` (requiere firma KC-API + passphrase cifrada, paginación obligatoria en bloques de 7 días).
     * **Binance**: Klines públicos, tickers y private endpoint `/api/v3/myTrades` (firma HMAC SHA256).
     * **BingX**: Klines públicos, tickers y private endpoint `/openApi/spot/v1/trade/myTrades`.

4. **Gestión de Estado**:
   * **Paquete**: `provider` (`WatchlistProvider`, `ChartProvider`, `TrackerProvider`).

---

## 3. Pruebas Realizadas y Datos de Referencia

* **Exchange Principal Probado**: **KuCoin**.
* **Par Principal de Pruebas**: **`ETH/USDT`** (en KuCoin API se formatea como `ETH-USDT`).
* **Operaciones reales sincronizadas**:
  * `BUY 0.2447831 ETH/USDT @ $1,633.55` (07-Jun-2026)
  * `SELL 0.24478 ETH/USDT @ $1,772.00` (17-Jun-2026)
  * `BUY 0.2302344 ETH/USDT @ $1,739.05` (22-Jun-2026)
  * `SELL 0.2302 ETH/USDT @ $1,876.12` (14-Jul-2026)
  * `SELL 0.1963 ETH/USDT @ $2,258.65` (19-Ago-2026)

---

## 4. Comandos Útiles de Consola (PowerShell / CMD)

* **Ejecutar en Windows Desktop**: `flutter run -d windows`
* **Lanzar Emulador Android**: `flutter emulators --launch invera_phone`
* **Ejecutar en Emulador Android**: `flutter run -d invera_phone`
* **Verificar dispositivos conectados**: `flutter devices`
* **Limpiar y regenerar paquetes**: `flutter clean && flutter pub get`

