# Manual Cuantitativo: Operativa Híbrida (Bot de Alta Rotación + Compras Spot Manuales)

## 1. Tesis Fundamental: La Sinergia de Doble Motor

Un error común en el trading algorítmico es intentar que una sola herramienta resuelva dinámicas de mercado opuestas. 

La estrategia híbrida resuelve esto dividiendo el capital en **dos motores matemáticos especializados e independientes** que se complementan sin estorbarse:

```
┌────────────────────────────────────────────────────────────────────────────────────────┐
│                                ESTRATEGIA HÍBRIDA BITCOIN                              │
├───────────────────────────────────────────┬────────────────────────────────────────────┤
│       MOTOR 1: EL BOT DE FLUJO            │       MOTOR 2: EL HODL ASIMÉTRICO          │
│   (`BtcQuantumCompoundRegimeStrategy`)    │          (Compras Manuales Spot)           │
├───────────────────────────────────────────┼────────────────────────────────────────────┤
│ • Objetivo: Rentabilizar el 75% del       │ • Objetivo: Capturar la expansión macro de │
│   tiempo (rangos, oscilaciones, rebotes). │   5x a 10x desde el fondo de mercado.      │
│ • Mecánica: TP fijo al +5.0%, Trailing al │ • Mecánica: Comprar en pánico extremo y    │
│   2.0% y Reciclaje Subsidiado en Cascada. │   retener en frío sin límite de Take Profit│
│ • Gestión: Automático, subcuenta KuCoin.  │ • Gestión: Manual, billetera fría / Spot.  │
│ • Virtud: Extrae flujo de caja constante. │ • Virtud: Máxima asimetría de capital.     │
│ • Debilidad: Malvende a +5% en el suelo.  │ • Debilidad: Cero flujo de caja en rangos. │
└───────────────────────────────────────────┴────────────────────────────────────────────┘
```

---

## 2. Matriz de Fases de Mercado: Cuándo Actuar y en Qué Motor

| Fase del Ciclo de Bitcoin | Métricas Cuantitativas de Activación | Acción sobre el BOT (Motor 1) | Acción MANUAL SPOT (Motor 2) |
| :--- | :--- | :--- | :--- |
| **1. Capitulación Extrema (Suelo de Ciclo)** | • Caída $> 65\%$ desde el ATH histórico.<br>• RSI Diario $< 25.0$.<br>• Precio muy por debajo de Daily EMA 200.<br>• Noticias de colapso/quiebras sistémicas. | **HIBERNACIÓN DEFENSIVA:**<br>• **PROHIBIDO inyectar capital al bot existente.**<br>• Si los tramos están llenos, dejarlos quietos.<br>• **Opcional:** Si se desea operar el rango del fondo (\$16k-\$25k), encender un **Sub-Bot Gemelo limpio** en subcuenta aislada con presupuesto acotado. | **COMPRA SPOT AGRESIVA (HODL):**<br>• **MOMENTO ÓPTIMO DE COMPRA MANUAL.**<br>• Desplegar compras en 2 o 3 bloques.<br>• Retirar a billetera fría o cuenta principal aislada.<br>• **NO poner estas monedas en el bot.** |
| **2. Confirmación y Ruptura Macro (The Golden Window)** | • Precio cruza y consolida con cierre diario/semanal sobre **Daily EMA 200**.<br>• Estructura alcista confirmada (Higher Highs).<br>• ADX $> 20$ en temporalidad diaria. | **MÁXIMO DESPLIEGUE / ESCALADO:**<br>• **MOMENTO ÓPTIMO PARA LANZAR UN BOT NUEVO O AMPLIAR BUDGET.**<br>• Inyectar el flujo de caja acumulado o capital fresco.<br>• La probabilidad de capital atrapado multianual es prácticamente cero en esta ventana. | **DETENER COMPRAS MANUALES:**<br>• Finalizar la fase de acumulación.<br>• Mantener la bolsa HODL intacta sin vender nada. |
| **3. Mercado Alcista en Expansión (Bull Run)** | • Precio $>$ EMA 50 $>$ EMA 200.<br>• Pendiente positiva constante en la media de 200 días. | **OPERATIVA AUTÓNOMA:**<br>• Dejar que el bot surfee la tendencia con su Trailing Stop del 2.0% y coseche ventas al +5.0%.<br>• Retirar beneficios periódicos en USDT. | **RETENCIÓN TOTAL:**<br>• Cero compras adicionales (evitar comprar en FOMO).<br>• Mantener la posición HODL. |
| **4. Euforia Parabólica (Techo de Ciclo)** | • Precio $> 60\% - 70\%$ por encima de Daily EMA 200.<br>• RSI Semanal $> 80.0$.<br>• Euforia mediática extrema y funding rates por las nubes. | **OPERATIVA BLOQUEADA A NUEVO CAPITAL:**<br>• **PROHIBIDO añadir capital nuevo al bot.**<br>• Reducir el `budget` base o extraer el flujo de caja realizado a USDT seguro antes de que el mercado se gire. | **TOMA PARCIAL DE BENEFICIOS:**<br>• Vender de forma escalonada entre un 25% y un 50% de la bolsa manual HODL hacia USDT.<br>• Este USDT será la munición para comprar el próximo suelo del ciclo. |

---

## 3. Protocolo de Aislamiento en KuCoin (Zero-Contamination)

Para evitar interferencias en los saldos, reconciliación errónea de órdenes o bloqueos del API, la separación de cuentas debe ser estricta:

1. **Subcuenta A (`criptobot_btc`):**
   - Dedicada **exclusivamente al bot algorítmico**.
   - Solo tiene el saldo asignado a la estrategia (ej. \$1,000 USDT).
   - El bot jamás debe detectar fondos ajenos para evitar sobredimensionar las órdenes.
2. **Cuenta Principal / Billetera Fría:**
   - Dedicada a las **compras manuales spot (HODL)**.
   - Las claves de API del bot no tienen acceso ni permisos sobre esta cuenta.
   - Las compras manuales se ejecutan por la interfaz web/móvil de KuCoin y las monedas quedan apartadas.

---

## 4. Evidencia Empírica: Los Números del Sistema Híbrido (2017 - 2026)

Analizando los 9 años de datos reales, comparemos los tres enfoques de gestión:

| Enfoque Operativo | Capital Depositado | Equidad Final (2026) | Flujo de Caja Cobrado | Comportamiento en Invierno |
| :--- | :---: | :---: | :---: | :--- |
| **A. Solo Buy & Hold Pasivo** | \$1,000 | \$12,303 USDT | \$0.00 USDT | Caída del -84% en 2018 y -77% en 2022 sin liquidez. |
| **B. Solo Bot Algorítmico (`BtcQuantumCompound`)** | \$1,000 | **\$20,950 USDT** | **+\$19,260 USDT** | Supera al mercado (+865% alfa), extrae casi 20x en caja y rescata capital en crashes. |
| **C. Sistema Híbrido (Bot \$1k + Compras Manuales en Suelos)** | \$1,000 en Bot<br>+\$1,000 suelo 2018<br>+\$1,000 suelo 2022<br>(Total: \$3,000) | **\$79,050 USDT**<br>(\$20.9k bot + \$58.1k bolsa spot HODL) | **+\$19,260 USDT** | **LA MÁXIMA EXPRESIÓN CUANTITATIVA:** El bot genera la caja diaria y las compras manuales de suelo multiplican el patrimonio exponencialmente. |

---

## 5. Checklist Operativo Paso a Paso para el Usuario

### ¿Cuándo encender un BOT NUEVO o ampliar capital?
- [ ] ¿El bot anterior cerró todos sus tramos o estoy usando una subcuenta aislada de presupuesto independiente?
- [ ] ¿El precio de Bitcoin se encuentra **POR ENCIMA de la Daily EMA 200** (aprox. vela diaria $> \text{EMA 200}$)?
- [ ] ¿El RSI de 14 días está en rango saludable ($< 60$)?
- [ ] **Decisión:** Si todo es afirmativo $\to$ **DESPLEGAR BOT / AMPLIAR CAPITAL**.

### ¿Cuándo hacer una COMPRA MANUAL SPOT?
- [ ] ¿Bitcoin ha sufrido una caída superior al **-60% o -70% desde su máximo histórico**?
- [ ] ¿El RSI Diario está en sobreventa extrema ($< 25$ o $< 20$)?
- [ ] ¿El bot principal ya completó la mayoría de sus tramos y no tiene liquidez disponible?
- [ ] **Decisión:** Si todo es afirmativo $\to$ **EJECUTAR COMPRA MANUAL SPOT EN LA CUENTA PRINCIPAL Y GUARDAR EN FRÍO. NO METER AL BOT.**
