# Propuesta Técnica: CryptoView - Clon Móvil de TabTrader

Esta propuesta detalla el diseño arquitectónico, la pila de tecnologías y las fases de desarrollo para **CryptoView**, un clon móvil de TabTrader enfocado en la lectura, visualización de gráficos, dibujo de líneas de soporte/resistencia, y un módulo especializado en el seguimiento y emparejamiento ("casamiento") de operaciones de compra/venta para calcular ganancias reales.

---

## 1. Pila de Tecnologías Propuesta (Tech Stack)

Para lograr una aplicación móvil híbrida, rápida, de alto rendimiento y con una estética premium, se propone la siguiente arquitectura:

### Frontend (Cliente Móvil/Web)
* **Framework**: **React (con Vite)**. Permite un desarrollo ágil, carga ultrarrápida y es ideal para aplicaciones de una sola página (SPA) que se comportan como apps nativas en dispositivos móviles.
* **Estilos (UI/UX)**: **Vanilla CSS Moderno (CSS Custom Properties, Grid, Flexbox)** con un diseño *Mobile-First*, modo oscuro de alto contraste (estilo terminal/TabTrader), y efectos de *Glassmorphism* (cristal esmerilado) para darle una apariencia sumamente premium.
* **Librería de Gráficos**: **Lightweight Charts (de TradingView)**. Es la librería oficial de alto rendimiento para gráficos financieros en entornos web y móviles. Consume poquísimos recursos y permite pintar velas, líneas de precios y objetos interactivos (líneas horizontales) de forma fluida en pantallas táctiles.
* **Base de Datos Local / Estado**: **IndexedDB / LocalStorage**. Para almacenar:
  * Configuraciones de la app y temas.
  * Claves API cifradas localmente (Read-Only).
  * Coordenadas de las líneas horizontales dibujadas por el usuario por cada par/moneda.
  * Historial de compras y ventas ingresadas o sincronizadas.
  * Relaciones de emparejamiento ("casamientos") de compras y ventas.

### Backend (Proxy / Opcional para producción)
* Dado que los exchanges de criptomonedas (Binance, KuCoin, BingX) implementan políticas estrictas de CORS (Cross-Origin Resource Sharing) en sus endpoints de API, el navegador web móvil bloqueará las peticiones directas.
* **Solución Propuesta**:
  1. **Desarrollo Inicial/Local**: Un servidor proxy ligero en Node.js/Express que redirecciona las llamadas de API del cliente a los exchanges, gestionando cabeceras y evitando problemas de CORS.
  2. **Producción**: Este mismo proxy puede desplegarse fácilmente en un servidor o como Serverless Functions (por ejemplo, en Vercel o Netlify).
  3. **Seguridad**: Las API keys se guardan en el cliente y se envían de forma segura al proxy, o se almacenan en memoria temporal.

---

## 2. Arquitectura de Módulos Clave

### A. Módulo de Gráficos y Visualización (Lectura)
* Conexión a las API públicas de Binance, KuCoin y BingX para obtener el listado de pares de trading (ej. BTC/USDT, ETH/USDT).
* Descarga de datos históricos de velas (K-lines) en diferentes temporalidades (1m, 5m, 15m, 1h, 4h, 1d).
* Interfaz táctil para dibujar, mover y eliminar líneas horizontales. Estas líneas se guardarán en el almacenamiento local asociadas al exchange y al par (ej. `binance:BTCUSDT -> [ {price: 34500, color: '#ff0000', id: 1} ]`).

### B. Módulo de Conexión de Cuentas (API Keys)
* Pantalla de configuración para agregar llaves de API (sólo lectura/read-only) para Binance, KuCoin y BingX.
* Indicador de estado de la conexión (Verde = Conectado, Rojo = Error/Inactivo).

### C. Módulo de Registro y Emparejamiento de Operaciones ("Casar" Compras y Ventas)
Este es el valor agregado principal de la aplicación.
* **Registro de Transacciones**: Una lista de compras y ventas. Cada registro tendrá:
  * ID único, Par (ej. BTC/USDT), Tipo (Compra/Venta), Precio, Cantidad, Comisión, Fecha, Exchange.
  * Estado: *Libre* (no emparejada) o *Casada* (emparejada).
* **Algoritmo de Casamiento (Matching Engine)**:
  * El usuario puede seleccionar una operación de **Compra** abierta y asociarla a una o varias operaciones de **Venta** (o viceversa).
  * **Cálculo de Ganancia**:
    $$\text{Ganancia Neta} = (\text{Precio Venta} \times \text{Cantidad}) - (\text{Precio Compra} \times \text{Cantidad}) - \text{Comisiones Totales}$$
  * Permite casamientos parciales (por ejemplo, si compraste 1 BTC y vendiste 0.5 BTC, se casa la mitad y el resto queda disponible como posición abierta).
  * Panel de Estadísticas: Ganancia total acumulada, porcentaje de operaciones ganadoras (Win Rate), operaciones abiertas (compras sin casar con ventas), y reportes detallados.

---

## 3. Plan de Implementación en Fases (Roadmap)

### Fase 1: Estructuración del Proyecto y Diseño Base (Mobile-First)
* Inicializar el proyecto con React + Vite.
* Diseñar la estructura de carpetas.
* Crear la hoja de estilos global (`index.css`) con el sistema de diseño oscuro premium (colores neón apagados, grises profundos, tipografía moderna, layouts adaptables a pantallas móviles).

### Fase 2: Implementación del Gráfico Interactivo (Lightweight Charts)
* Crear el componente de gráfico interactivo.
* Conectar con el API público de Binance para obtener velas históricas en tiempo real.
* Añadir herramientas de dibujo: botón para colocar una línea horizontal al hacer clic/tap en el gráfico y guardarla en LocalStorage.

### Fase 3: Integración de Multi-Exchange (Binance, KuCoin, BingX)
* Crear la capa de servicios para consultar precios y tickers de los tres exchanges usando un servidor proxy local para evitar CORS.
* Crear la barra de búsqueda y navegación para cambiar rápidamente de exchange y de par.

### Fase 4: Registro de Operaciones y Motor de Casamiento
* Crear base de datos local (IndexedDB o LocalStorage mejorado) para almacenar transacciones.
* Desarrollar la UI para registrar compras/ventas manualmente (y simular la lectura de historial de órdenes vía API).
* Implementar la interfaz para seleccionar compras y ventas y "casarlas", mostrando la ganancia/pérdida neta de la operación cerrada.

### Fase 5: PWA e Instalación Móvil
* Configurar la app como Progressive Web App (PWA) para que se pueda agregar a la pantalla de inicio del teléfono inteligente y funcione a pantalla completa sin barra de navegación del navegador web.

---

## 4. Diseño Visual Propuesto (Aesthetics)
* **Fondo**: `#0b0e11` (Negro azulado profundo, similar al modo oscuro de Binance/TabTrader).
* **Color Primario (Acento)**: `#00ffcc` (Cian brillante) o `#f0b90b` (Amarillo oro).
* **Velas Alcistas**: `#0ecb81` (Verde esmeralda).
* **Velas Bajistas**: `#f6465d` (Rojo neón).
* **Efectos**: Bordes sutiles con gradientes, fondos con `backdrop-filter: blur(10px)` (glassmorphism) en modales y menús de navegación móvil.
