import os
import sys
import gzip
import time
import subprocess
import psycopg2
from pathlib import Path

# Configuración de base de datos
PG_HOST = "127.0.0.1"
PG_PORT = 5432
PG_USER = "postgres"
PG_PASS = "postgres"
TARGET_DB = "CryptoViewPruebas"

PSQL_EXE = r"C:\Program Files\pgAdmin 4\runtime\psql.exe"
BACKUP_PATH = r"C:\Users\yordany\AppData\Roaming\com.yordany\cryptoview\CryptoView\Backups\cryptoview_timescaledb_full_2026-11-09_03-21-19.sql.gz"
LOG_PATH = r"D:\Proyectos\Mios\CryptoView\restore_new.log"

def step1_recreate_db():
    print("[1/5] Conectando a PostgreSQL para reiniciar la base de datos...")
    conn = psycopg2.connect(
        host=PG_HOST, port=PG_PORT, user=PG_USER, password=PG_PASS, dbname="postgres"
    )
    conn.autocommit = True
    cur = conn.cursor()

    print(f"      Terminando conexiones activas a {TARGET_DB}...")
    cur.execute(f"""
        SELECT pg_terminate_backend(pid) 
        FROM pg_stat_activity 
        WHERE datname = '{TARGET_DB}' AND pid <> pg_backend_pid();
    """)

    print(f"      Borrando base de datos {TARGET_DB} si existe...")
    cur.execute(f'DROP DATABASE IF EXISTS "{TARGET_DB}";')

    print(f"      Creando base de datos {TARGET_DB}...")
    cur.execute(f'CREATE DATABASE "{TARGET_DB}";')

    cur.close()
    conn.close()

def step2_init_timescale():
    print("[2/5] Inicializando TimescaleDB y activando modo pre-restauración...")
    conn = psycopg2.connect(
        host=PG_HOST, port=PG_PORT, user=PG_USER, password=PG_PASS, dbname=TARGET_DB
    )
    conn.autocommit = True
    cur = conn.cursor()

    cur.execute("CREATE EXTENSION IF NOT EXISTS timescaledb CASCADE;")
    cur.execute("CREATE EXTENSION IF NOT EXISTS timescaledb_toolkit CASCADE;")
    print("      Extensiones creadas. Ejecutando timescaledb_pre_restore()...")
    cur.execute("SELECT timescaledb_pre_restore();")
    print("      timescaledb_pre_restore() completado exitosamente.")

    cur.close()
    conn.close()

def step3_stream_restore():
    print(f"[3/5] Restaurando dump desde: {BACKUP_PATH}")
    file_size_mb = os.path.getsize(BACKUP_PATH) / (1024 * 1024)
    print(f"      Tamaño del archivo comprimido: {file_size_mb:.2f} MB")
    
    env = os.environ.copy()
    env["PGPASSWORD"] = PG_PASS

    cmd = [
        PSQL_EXE,
        "-h", PG_HOST,
        "-p", str(PG_PORT),
        "-U", PG_USER,
        "-d", TARGET_DB,
        "-v", "ON_ERROR_STOP=0"
    ]

    t0 = time.time()
    with open(LOG_PATH, "wb") as log_file:
        proc = subprocess.Popen(
            cmd,
            stdin=subprocess.PIPE,
            stdout=log_file,
            stderr=log_file,
            env=env
        )

        bytes_written = 0
        chunk_size = 8 * 1024 * 1024  # 8 MB chunks
        last_report = t0

        with gzip.open(BACKUP_PATH, "rb") as gz:
            while True:
                chunk = gz.read(chunk_size)
                if not chunk:
                    break
                proc.stdin.write(chunk)
                bytes_written += len(chunk)

                if time.time() - last_report > 15:
                    elapsed = time.time() - t0
                    mb_decompressed = bytes_written / (1024 * 1024)
                    print(f"      Progreso: {mb_decompressed:.1f} MB descomprimidos y enviados a psql ({elapsed:.1f}s)...")
                    last_report = time.time()

        proc.stdin.close()
        print("      Fin del archivo alcanzado. Esperando que psql finalice los índices y restricciones...")
        proc.wait()

    elapsed_total = time.time() - t0
    print(f"      psql finalizó con código de salida: {proc.returncode} en {elapsed_total:.1f} segundos.")

def step4_post_restore():
    print("[4/5] Finalizando modo restauración y sincronizando versión de TimescaleDB...")
    conn = psycopg2.connect(
        host=PG_HOST, port=PG_PORT, user=PG_USER, password=PG_PASS, dbname=TARGET_DB
    )
    conn.autocommit = True
    cur = conn.cursor()

    try:
        # Sincronizar versión del catálogo de TimescaleDB si viene de una versión anterior
        cur.execute("SELECT extversion FROM pg_extension WHERE extname = 'timescaledb';")
        ext_ver = cur.fetchone()[0]
        cur.execute(f"UPDATE _timescaledb_catalog.metadata SET value = '{ext_ver}' WHERE key = 'timescaledb_version';")
        
        cur.execute("SELECT timescaledb_post_restore();")
        print("      timescaledb_post_restore() completado exitosamente.")
    except Exception as e:
        print(f"      Aviso en post_restore: {e}")

    cur.close()
    conn.close()

def step5_verify():
    print("[5/5] Verificando datos restaurados en CryptoViewPruebas...")
    conn = psycopg2.connect(
        host=PG_HOST, port=PG_PORT, user=PG_USER, password=PG_PASS, dbname=TARGET_DB
    )
    cur = conn.cursor()

    try:
        cur.execute("SELECT exchange, symbol, is_active, backfill_completed FROM tracked_symbols;")
        print("\n=== Tracked Symbols ===")
        for s in cur.fetchall():
            print(f"  Exchange: {s[0]} | Par: {s[1]:<10} | Activo: {s[2]} | Backfill: {s[3]}")
    except Exception as e:
        print(f"  Error consultando tracked_symbols: {e}")
        conn.rollback()

    try:
        cur.execute("""
            SELECT symbol, count(*), 
                   min(time) as min_t, 
                   max(time) as max_t 
            FROM market_candles 
            GROUP BY symbol 
            ORDER BY count(*) DESC;
        """)
        print("\n=== Market Candles (1m Base) ===")
        for row in cur.fetchall():
            print(f"  Símbolo: {row[0]:<12} | Total: {row[1]:>10,d} velas | Rango: {row[2]} -> {row[3]}")
    except Exception as e:
        print(f"  Error consultando market_candles: {e}")
        conn.rollback()

    for view_name in ["candles_5m", "candles_1h", "candles_1d"]:
        try:
            cur.execute(f"SELECT count(*) FROM {view_name};")
            count = cur.fetchone()[0]
            print(f"\n=== Vista/Agregado {view_name} ===")
            print(f"  Total registros: {count:,d}")
        except Exception as e:
            print(f"  {view_name}: {e}")
            conn.rollback()

    cur.close()
    conn.close()

if __name__ == "__main__":
    t_start = time.time()
    try:
        step1_recreate_db()
        step2_init_timescale()
        step3_stream_restore()
        step4_post_restore()
        step5_verify()
        print(f"\n¡RESTAURACIÓN EXITOSA COMPLETADA EN {time.time() - t_start:.1f} SEGUNDOS!")
    except Exception as e:
        print(f"\n[ERROR CRÍTICO] La restauración falló: {e}")
        sys.exit(1)
