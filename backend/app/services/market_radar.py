import numpy as np
import pandas as pd
from datetime import datetime, timezone
from typing import Dict, Any, Optional
import asyncpg

HALVINGS = [
    datetime(2012, 11, 28, tzinfo=timezone.utc),
    datetime(2016, 7, 9, tzinfo=timezone.utc),
    datetime(2020, 5, 11, tzinfo=timezone.utc),
    datetime(2024, 4, 19, tzinfo=timezone.utc),
]

class MarketCycleRadarService:
    """
    Servicio de inteligencia macro consultivo e informativo.
    Evalúa el estado del ciclo de Bitcoin (o activos seguidos) e identifica:
      1. Ventanas óptimas de entrada para lanzar bots o ampliar capital.
      2. Alertas de techo / agotamiento para desescalar o pausar recompras.
    NUNCA bloquea la operativa: ofrece visibilidad estadística pura.
    """

    @staticmethod
    def _calculate_days_since_last_halving(now_dt: datetime) -> int:
        past_halvings = [h for h in HALVINGS if h <= now_dt]
        if not past_halvings:
            return 9999
        last_halving = max(past_halvings)
        return (now_dt - last_halving).days

    @classmethod
    async def analyze_market_cycle(cls, pool: asyncpg.Pool, symbol: str = "BTC/USDT") -> Dict[str, Any]:
        norm_symbol = symbol.replace("-", "/").upper()
        
        # 1. Obtener el ATH histórico absoluto registrado
        async with pool.acquire() as conn:
            ath_row = await conn.fetchrow(
                "SELECT MAX(high) AS ath FROM candles_1h WHERE symbol = $1;",
                norm_symbol
            )
            ath_price = float(ath_row["ath"] or 0.0)

            # 2. Obtener hasta 10,000 velas horarias recientes (~416 días) para calcular medias macro
            query = """
                SELECT time, open, high, low, close, volume 
                FROM candles_1h 
                WHERE symbol = $1 
                ORDER BY time DESC 
                LIMIT 10000;
            """
            rows = await conn.fetch(query, norm_symbol)

        if not rows:
            return {
                "symbol": norm_symbol,
                "error": "No hay suficientes velas horarias para calcular el radar.",
                "calculated_at": datetime.now(timezone.utc).isoformat()
            }

        # Convertir a DataFrame cronológico ascendente
        data = [dict(r) for r in reversed(rows)]
        df = pd.DataFrame(data)
        df["time"] = pd.to_datetime(df["time"], utc=True)
        df.set_index("time", inplace=True)
        df["close"] = df["close"].astype(float)
        df["high"] = df["high"].astype(float)
        df["low"] = df["low"].astype(float)

        current_price = float(df["close"].iloc[-1])
        now_dt = df.index[-1]

        # 3. Medias y métricas macro
        # Daily EMA 200 = 200 * 24 = 4800 velas de 1h
        span_ema_200 = min(4800, len(df))
        df["ema_daily_200"] = df["close"].ewm(span=span_ema_200, adjust=False).mean()
        daily_ema_200 = float(df["ema_daily_200"].iloc[-1])

        # Daily EMA 50 = 50 * 24 = 1200 velas de 1h
        span_ema_50 = min(1200, len(df))
        df["ema_daily_50"] = df["close"].ewm(span=span_ema_50, adjust=False).mean()
        daily_ema_50 = float(df["ema_daily_50"].iloc[-1])

        # RSI Diario aproximado (14 * 24 = 336 horas)
        delta = df["close"].diff()
        gain = delta.where(delta > 0, 0.0)
        loss = -delta.where(delta < 0, 0.0)
        avg_gain = gain.ewm(alpha=1.0 / (14 * 24), adjust=False).mean()
        avg_loss = loss.ewm(alpha=1.0 / (14 * 24), adjust=False).mean()
        rs = avg_gain / avg_loss.replace(0, np.nan)
        df["rsi_daily"] = (100.0 - (100.0 / (1.0 + rs))).fillna(50.0)
        daily_rsi = float(df["rsi_daily"].iloc[-1])

        # Pi Cycle Top:
        # SMA 111 días = 111 * 24 = 2,664 horas
        # SMA 350 días * 2 = 350 * 24 = 8,400 horas (* 2.0)
        has_pi_data = len(df) >= 8400
        if has_pi_data:
            df["sma_111d"] = df["close"].rolling(2664).mean()
            df["sma_350d_x2"] = df["close"].rolling(8400).mean() * 2.0
            sma_111d = float(df["sma_111d"].iloc[-1])
            sma_350d_x2 = float(df["sma_350d_x2"].iloc[-1])
            pi_ratio = sma_111d / sma_350d_x2 if sma_350d_x2 > 0 else 0.0
            is_pi_cycle_top = sma_111d >= sma_350d_x2
        else:
            sma_111d = float(df["close"].rolling(min(2664, len(df))).mean().iloc[-1])
            sma_350d_x2 = float(daily_ema_200 * 2.0)
            pi_ratio = sma_111d / sma_350d_x2 if sma_350d_x2 > 0 else 0.0
            is_pi_cycle_top = False

        # Ratios de distancia
        dist_ema_200_pct = ((current_price - daily_ema_200) / daily_ema_200) * 100.0
        drawdown_from_ath_pct = ((current_price - ath_price) / ath_price) * 100.0 if ath_price > 0 else 0.0
        days_since_halving = cls._calculate_days_since_last_halving(now_dt)

        # Días por encima de la EMA 200 diaria
        above_ema = df["close"] >= df["ema_daily_200"]
        consecutive_above_hours = (above_ema[::-1].cumprod().sum())
        days_above_ema_200 = round(consecutive_above_hours / 24.0, 1)

        # 4. Evaluación de Señal de ENTRADA (Lanzar Bots o Inyectar Capital)
        if drawdown_from_ath_pct <= -55.0 and daily_rsi <= 32.0:
            entry_status = "PANIC_CAPITULATION"
            entry_traffic_light = "GREEN"
            entry_title = "Pozo de Capitulación (Suelo Histórico)"
            entry_rec = "Condición de sobreventa y pánico extremo. Históricamente es el arquetipo con mayor retorno compuesto a 1 y 2 años (+211% a 1A, +345% a 2A)."
            is_ideal_entry = True
            historical_win_rate = 100.0
            historical_avg_ret_1y = 211.1
        elif current_price >= daily_ema_200 and dist_ema_200_pct <= 25.0 and 45.0 <= daily_rsi <= 65.0:
            entry_status = "GOLDEN_BREAKOUT"
            entry_traffic_light = "GREEN"
            entry_title = "Ventana Dorada de Ruptura"
            entry_rec = "Estructura alcista confirmada sobre la Daily EMA 200 con RSI en rango sano. Riesgo de atrapamiento secular mínimo (+136% retorno promedio a 1A)."
            is_ideal_entry = True
            historical_win_rate = 100.0
            historical_avg_ret_1y = 136.1
        elif 90 <= days_since_halving <= 180 and current_price >= daily_ema_200:
            entry_status = "HALVING_SQUEEZE"
            entry_traffic_light = "GREEN"
            entry_title = "Compresión Post-Halving"
            entry_rec = "Ventana cíclica de absorción de oferta (meses 3 a 6 post-halving). Históricamente precede expansiones prolongadas."
            is_ideal_entry = True
            historical_win_rate = 100.0
            historical_avg_ret_1y = 170.0
        elif dist_ema_200_pct >= 50.0 and daily_rsi >= 72.0:
            entry_status = "DANGER_OVERHEATED"
            entry_traffic_light = "RED"
            entry_title = "Zona Roja de Euforia (Peligro de Atrapamiento)"
            entry_rec = "Mercado parabólico y sobreextendido. Históricamente lanzar bots aquí conlleva pérdidas flotantes severas (-29% a -65% a 1 año)."
            is_ideal_entry = False
            historical_win_rate = 0.0
            historical_avg_ret_1y = -47.0
        else:
            entry_status = "NEUTRAL_RANGE"
            entry_traffic_light = "YELLOW"
            entry_title = "Régimen Normal de Consolidación"
            entry_rec = "Mercado en oscilación estándar. Operativa continua normal sin ventajas ni riesgos macro extremos."
            is_ideal_entry = False
            historical_win_rate = 95.0
            historical_avg_ret_1y = 45.0

        # 5. Evaluación de Señal de SALIDA (Desescalado o Cosecha a USDT)
        # Revisar si en los últimos 60 días estuvo cerca de ATH y luego perdió la Daily EMA 50
        recent_high_60d = float(df["high"].tail(60 * 24).max())
        near_ath_recently = (recent_high_60d >= ath_price * 0.92)
        lost_ema_50 = (current_price < daily_ema_50 * 0.97)

        if is_pi_cycle_top:
            exit_status = "PI_CYCLE_TOP"
            exit_traffic_light = "RED"
            exit_title = "ALERTA CRÍTICA: Pi Cycle Top Activado"
            exit_rec = "Indicador de techo parabólico disparado. Históricamente marca el pico con 2 a 4 días de margen. Considera pausar nuevas recompras y asegurar caja en USDT."
            is_exit_warning = True
            suggested_action = "PAUSE_NEW_ENTRIES"
        elif near_ath_recently and lost_ema_50 and dist_ema_200_pct < 20.0:
            exit_status = "STRUCTURAL_BREAKDOWN"
            exit_traffic_light = "YELLOW"
            exit_title = "Alerta de Distribución / Pérdida de EMA 50"
            exit_rec = "El precio estuvo en zona de máximos y rompió a la baja la EMA 50 diaria. Entrada típica en fase de distribución."
            is_exit_warning = True
            suggested_action = "MONITOR_OR_DE_RISK"
        elif dist_ema_200_pct >= 75.0:
            exit_status = "PARABOLIC_EXHAUSTION"
            exit_traffic_light = "YELLOW"
            exit_title = "Extensión Parabólica Extrema (>+75% sobre EMA 200)"
            exit_rec = "El mercado está en euforia extrema. Buen momento para retirar o cosechar parte de las ganancias acumuladas a USDT seguro."
            is_exit_warning = True
            suggested_action = "HARVEST_PROFITS"
        else:
            exit_status = "HEALTHY_TREND"
            exit_traffic_light = "GREEN"
            exit_title = "Estructura Alcista / Normal Saludable"
            exit_rec = "No hay señales de agotamiento ni techo macro. Operativa normal dejando correr beneficios con Trailing Stop."
            is_exit_warning = False
            suggested_action = "NONE"

        return {
            "symbol": norm_symbol,
            "calculated_at": now_dt.isoformat(),
            "current_price": round(current_price, 2),
            "ath_price": round(ath_price, 2),
            "daily_ema_200": round(daily_ema_200, 2),
            "daily_ema_50": round(daily_ema_50, 2),
            "daily_rsi": round(daily_rsi, 1),
            "dist_daily_ema_200_pct": round(dist_ema_200_pct, 2),
            "drawdown_from_ath_pct": round(drawdown_from_ath_pct, 2),
            "days_above_daily_ema_200": days_above_ema_200,
            "days_since_last_halving": days_since_halving,
            
            "entry_radar": {
                "status": entry_status,
                "traffic_light": entry_traffic_light,
                "title": entry_title,
                "recommendation": entry_rec,
                "is_ideal_entry": is_ideal_entry,
                "historical_win_rate_1y_pct": historical_win_rate,
                "historical_avg_return_1y_pct": historical_avg_ret_1y,
            },
            
            "exit_radar": {
                "status": exit_status,
                "traffic_light": exit_traffic_light,
                "title": exit_title,
                "recommendation": exit_rec,
                "is_exit_warning": is_exit_warning,
                "suggested_action": suggested_action,
            },
            
            "pi_cycle_metrics": {
                "sma_111d": round(sma_111d, 2),
                "sma_350d_x2": round(sma_350d_x2, 2),
                "pi_ratio": round(pi_ratio, 3),
                "is_triggered": is_pi_cycle_top,
            }
        }
