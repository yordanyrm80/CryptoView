import os
import psycopg2
import pandas as pd
import numpy as np

DB_URL = "postgresql://postgres:postgres@127.0.0.1:5432/CryptoViewPruebas"

def analyze():
    conn = psycopg2.connect(DB_URL)
    
    # 1. Cargar velas diarias de ETH y BTC
    query = """
        SELECT symbol, time, open, high, low, close, volume 
        FROM candles_1d 
        WHERE symbol IN ('ETH/USDT', 'BTC/USDT')
        ORDER BY symbol, time ASC;
    """
    df = pd.read_sql(query, conn)
    conn.close()

    df_eth = df[df['symbol'] == 'ETH/USDT'].copy().set_index('time')
    df_btc = df[df['symbol'] == 'BTC/USDT'].copy().set_index('time')

    # Alinear fechas comunes
    common_idx = df_eth.index.intersection(df_btc.index)
    df_eth = df_eth.loc[common_idx]
    df_btc = df_btc.loc[common_idx]

    print("================================================================")
    print("ANÁLISIS COMPARATIVO DE LA NATURALEZA DE ETH vs BTC (2017-2026)")
    print("================================================================")
    print(f"Rango de datos analizado: {common_idx[0].date()} a {common_idx[-1].date()} ({len(common_idx)} días)")

    # 1. Retorno Buy & Hold
    eth_bh = (df_eth['close'].iloc[-1] / df_eth['close'].iloc[0] - 1) * 100
    btc_bh = (df_btc['close'].iloc[-1] / df_btc['close'].iloc[0] - 1) * 100
    print(f"\n1. Retorno Buy & Hold Total:")
    print(f"   ETH/USDT: {eth_bh:,.2f}% (${df_eth['close'].iloc[0]:.2f} -> ${df_eth['close'].iloc[-1]:.2f})")
    print(f"   BTC/USDT: {btc_bh:,.2f}% (${df_btc['close'].iloc[0]:.2f} -> ${df_btc['close'].iloc[-1]:.2f})")

    # 2. Volatilidad Diaria (Retornos logarítmicos y porcentuales)
    df_eth['ret'] = df_eth['close'].pct_change()
    df_btc['ret'] = df_btc['close'].pct_change()

    eth_vol_daily = df_eth['ret'].std() * 100
    btc_vol_daily = df_btc['ret'].std() * 100
    eth_vol_annual = eth_vol_daily * np.sqrt(365)
    btc_vol_annual = btc_vol_daily * np.sqrt(365)

    print(f"\n2. Volatilidad de Retornos:")
    print(f"   ETH Volatilidad diaria:  {eth_vol_daily:.2f}% | Anualizada: {eth_vol_annual:.2f}%")
    print(f"   BTC Volatilidad diaria:  {btc_vol_daily:.2f}% | Anualizada: {btc_vol_annual:.2f}%")
    print(f"   Ratio Volatilidad ETH/BTC: {eth_vol_daily / btc_vol_daily:.2f}x (ETH es {(eth_vol_daily/btc_vol_daily - 1)*100:.1f}% más volátil)")

    # 3. Amplitud Diaria Promedio (High - Low) / Open (ATR intrínseco diario)
    df_eth['daily_range_pct'] = ((df_eth['high'] - df_eth['low']) / df_eth['open']) * 100
    df_btc['daily_range_pct'] = ((df_btc['high'] - df_btc['low']) / df_btc['open']) * 100

    print(f"\n3. Rango Diario Promedio (High-Low)/Open:")
    print(f"   ETH Promedio Rango Diario: {df_eth['daily_range_pct'].mean():.2f}% (Mediana: {df_eth['daily_range_pct'].median():.2f}%)")
    print(f"   BTC Promedio Rango Diario: {df_btc['daily_range_pct'].mean():.2f}% (Mediana: {df_btc['daily_range_pct'].median():.2f}%)")

    # 4. Caídas Máximas Históricas (Max Drawdowns de cada ciclo)
    for name, d in [("ETH", df_eth), ("BTC", df_btc)]:
        d['cummax'] = d['close'].cummax()
        d['dd'] = (d['close'] - d['cummax']) / d['cummax'] * 100
    
    print(f"\n4. Max Drawdown Histórico Total:")
    print(f"   ETH Max Drawdown: {df_eth['dd'].min():.2f}%")
    print(f"   BTC Max Drawdown: {df_btc['dd'].min():.2f}%")

    # Caídas en los mercados bajistas clave:
    # 2018 Bear Market (2018-01 a 2018-12)
    dd_2018_eth = ((df_eth.loc['2018-01-01':'2018-12-31', 'close'].min() / df_eth.loc['2018-01-01':'2018-01-31', 'close'].max()) - 1) * 100
    dd_2018_btc = ((df_btc.loc['2018-01-01':'2018-12-31', 'close'].min() / df_btc.loc['2018-01-01':'2018-01-31', 'close'].max()) - 1) * 100

    # 2022 Bear Market (2021-11 a 2022-12)
    dd_2022_eth = ((df_eth.loc['2021-11-01':'2022-12-31', 'close'].min() / df_eth.loc['2021-11-01':'2021-12-01', 'close'].max()) - 1) * 100
    dd_2022_btc = ((df_btc.loc['2021-11-01':'2022-12-31', 'close'].min() / df_btc.loc['2021-11-01':'2021-12-01', 'close'].max()) - 1) * 100

    print(f"\n5. Caídas en Inviernos Cripto:")
    print(f"   Invierno 2018:  ETH cayó {dd_2018_eth:.2f}%  vs  BTC cayó {dd_2018_btc:.2f}%")
    print(f"   Invierno 2022:  ETH cayó {dd_2022_eth:.2f}%  vs  BTC cayó {dd_2022_btc:.2f}%")

    # 6. Distribución de Velas con movimiento > 4.5% y > 7.0%
    eth_days_gt_4_5 = (df_eth['ret'].abs() > 0.045).mean() * 100
    btc_days_gt_4_5 = (df_btc['ret'].abs() > 0.045).mean() * 100
    eth_days_gt_7 = (df_eth['ret'].abs() > 0.07).mean() * 100
    btc_days_gt_7 = (df_btc['ret'].abs() > 0.07).mean() * 100

    print(f"\n6. Frecuencia de Movimientos Fuertes:")
    print(f"   Días con cambio absoluto > 4.5%: ETH {eth_days_gt_4_5:.1f}% de los días | BTC {btc_days_gt_4_5:.1f}% de los días")
    print(f"   Días con cambio absoluto > 7.0%: ETH {eth_days_gt_7:.1f}% de los días | BTC {btc_days_gt_7:.1f}% de los días")

if __name__ == "__main__":
    analyze()
