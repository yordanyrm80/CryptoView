import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import psycopg2
import pandas as pd
from src.indicators.technical import TechnicalIndicators

DB_URL = "postgresql://postgres:postgres@127.0.0.1:5432/CryptoViewPruebas"

def diagnose():
    conn = psycopg2.connect(DB_URL)
    query = """
        SELECT time as dt, open, high, low, close, volume 
        FROM candles_1h 
        WHERE symbol = 'ETH/USDT' 
        ORDER BY time ASC;
    """
    df = pd.read_sql(query, conn)
    conn.close()

    df['dt'] = pd.to_datetime(df['dt'], utc=True)
    df.set_index('dt', inplace=True)
    df = TechnicalIndicators.apply_all(df)

    last = df.iloc[-1]
    ath = df['close'].max()
    dd_ath = ((last['close'] - ath) / ath) * 100.0
    dist_ema200 = ((last['close'] - last['ema_daily_200']) / last['ema_daily_200']) * 100.0

    print("==================================================================")
    print(f"ESTADO TÉCNICO Y RADAR DE ETHEREUM (Fecha: {last.name})")
    print("==================================================================")
    print(f"Precio Actual ETH:             ${last['close']:,.2f}")
    print(f"Máximo Histórico (ATH):        ${ath:,.2f}")
    print(f"Descuento desde ATH:           {dd_ath:.2f}%")
    print(f"Daily EMA 200 (Macro):         ${last['ema_daily_200']:,.2f}")
    print(f"Distancia vs Daily EMA 200:   {dist_ema200:+.2f}%")
    print(f"RSI 14 (1h):                   {last['rsi_14']:.2f}")
    print(f"ADX 14:                        {last['adx_14']:.2f}")

    # Determinar zona del radar
    print("\n--- DIAGNÓSTICO DEL RADAR DE LANZAMIENTO PARA ETH ---")
    if last['close'] >= last['ema_daily_200'] and 45.0 <= last['rsi_14'] <= 65.0:
        print("[ZONA VERDE / VENTANA DORADA]: ETH consolidando sobre Daily EMA 200.")
        print("  -> MOMENTO IDEAL DE ALTA VELOCIDAD: Rotación máxima y compounding acelerado (+182.9% medio a 1A).")
    elif dd_ath <= -50.0 and last['rsi_14'] <= 35.0:
        print("[ZONA DORADA / POZO DE CAPITULACIÓN]: Caída profunda >50% con RSI en sobreventa.")
        print("  -> MOMENTO IDEAL DE MÁXIMA ASIMETRÍA: Compra en suelos generacionales con 0 días de capital atrapado (+136% medio a 1A).")
    elif last['close'] < last['ema_daily_200']:
        print("[ZONA AMARILLA / ACUMULACIÓN DEVALUADA]: ETH cotiza con -56% de descuento desde ATH, pero aún por debajo de la Daily EMA 200.")
        print("  -> Si buscas acumulación asimétrica barata: Excelente nivel (descuento del 56%).")
        print("  -> Si buscas velocidad inmediata sin esperar: Esperar confirmación de superación de Daily EMA 200 ($" + f"{last['ema_daily_200']:,.0f}) para evitar semanas de consolidación lateral.")
    else:
        print("[ZONA NEUTRAL]: Condiciones estándar de mercado.")

if __name__ == "__main__":
    diagnose()
