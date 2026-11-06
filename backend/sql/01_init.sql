-- 1. Activar extensión TimescaleDB
CREATE EXTENSION IF NOT EXISTS timescaledb CASCADE;

-- 2. Tabla de Símbolos en Seguimiento Dinámico
CREATE TABLE IF NOT EXISTS tracked_symbols (
    exchange VARCHAR(32) NOT NULL,
    symbol VARCHAR(32) NOT NULL,
    is_active BOOLEAN DEFAULT TRUE,
    backfill_completed BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    PRIMARY KEY (exchange, symbol)
);

-- Monedas iniciales por defecto (KuCoin)
INSERT INTO tracked_symbols (exchange, symbol) VALUES 
    ('kucoin', 'BTC/USDT')
ON CONFLICT DO NOTHING;

-- 3. Tabla de API Keys de Exchanges (Guardadas con Cifrado AES-256)
CREATE TABLE IF NOT EXISTS api_keys (
    exchange VARCHAR(32) PRIMARY KEY,
    api_key_encrypted TEXT NOT NULL,
    api_secret_encrypted TEXT NOT NULL,
    api_passphrase_encrypted TEXT DEFAULT '',
    is_active BOOLEAN DEFAULT TRUE,
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 4. Tabla de Velas de Mercado (Series Temporales Base: 1 Minuto)
CREATE TABLE IF NOT EXISTS market_candles (
    time TIMESTAMPTZ NOT NULL,
    exchange VARCHAR(32) NOT NULL,
    symbol VARCHAR(32) NOT NULL,
    open DOUBLE PRECISION NOT NULL,
    high DOUBLE PRECISION NOT NULL,
    low DOUBLE PRECISION NOT NULL,
    close DOUBLE PRECISION NOT NULL,
    volume DOUBLE PRECISION NOT NULL DEFAULT 0.0,
    PRIMARY KEY (time, exchange, symbol)
);

-- Convertir a Hypertable de TimescaleDB particionada por tiempo
SELECT create_hypertable('market_candles', 'time', if_not_exists => TRUE);

-- Índice optimizado para búsquedas por exchange, símbolo y tiempo descendente
CREATE INDEX IF NOT EXISTS idx_candles_lookup 
ON market_candles (exchange, symbol, time DESC);

-- Compresión columnar automática de TimescaleDB (comprime >90% los datos de más de 7 días)
ALTER TABLE market_candles SET (
    timescaledb.compress,
    timescaledb.compress_segmentby = 'exchange, symbol',
    timescaledb.compress_orderby = 'time DESC'
);

SELECT add_compression_policy('market_candles', INTERVAL '7 days', if_not_exists => TRUE);

-- Vistas Materializadas Continuas (Continuous Aggregates) de TimescaleDB
CREATE MATERIALIZED VIEW IF NOT EXISTS candles_5m
WITH (timescaledb.continuous, timescaledb.materialized_only = false) AS
SELECT
    time_bucket('5 minutes', time) AS time,
    exchange,
    symbol,
    first(open, time) AS open,
    max(high) AS high,
    min(low) AS low,
    last(close, time) AS close,
    sum(volume) AS volume
FROM market_candles
GROUP BY time_bucket('5 minutes', time), exchange, symbol
WITH NO DATA;

CREATE MATERIALIZED VIEW IF NOT EXISTS candles_1h
WITH (timescaledb.continuous, timescaledb.materialized_only = false) AS
SELECT
    time_bucket('1 hour', time) AS time,
    exchange,
    symbol,
    first(open, time) AS open,
    max(high) AS high,
    min(low) AS low,
    last(close, time) AS close,
    sum(volume) AS volume
FROM market_candles
GROUP BY time_bucket('1 hour', time), exchange, symbol
WITH NO DATA;

CREATE MATERIALIZED VIEW IF NOT EXISTS candles_1d
WITH (timescaledb.continuous, timescaledb.materialized_only = false) AS
SELECT
    time_bucket('1 day', time) AS time,
    exchange,
    symbol,
    first(open, time) AS open,
    max(high) AS high,
    min(low) AS low,
    last(close, time) AS close,
    sum(volume) AS volume
FROM market_candles
GROUP BY time_bucket('1 day', time), exchange, symbol
WITH NO DATA;

-- Políticas de refresco automático para las vistas continuas
SELECT add_continuous_aggregate_policy('candles_5m',
    start_offset => INTERVAL '1 day',
    end_offset => INTERVAL '1 minute',
    schedule_interval => INTERVAL '1 minute',
    if_not_exists => TRUE);

SELECT add_continuous_aggregate_policy('candles_1h',
    start_offset => INTERVAL '7 days',
    end_offset => INTERVAL '5 minutes',
    schedule_interval => INTERVAL '5 minutes',
    if_not_exists => TRUE);

SELECT add_continuous_aggregate_policy('candles_1d',
    start_offset => INTERVAL '30 days',
    end_offset => INTERVAL '1 hour',
    schedule_interval => INTERVAL '1 hour',
    if_not_exists => TRUE);

-- 5. Tabla de Operaciones de Cuenta (Trades / Fills privados)
CREATE TABLE IF NOT EXISTS account_trades (
    id BIGSERIAL PRIMARY KEY,
    trade_id VARCHAR(64) NOT NULL,
    order_id VARCHAR(64),
    exchange VARCHAR(32) NOT NULL,
    symbol VARCHAR(32) NOT NULL,
    side VARCHAR(8) NOT NULL, -- 'buy' o 'sell'
    price DOUBLE PRECISION NOT NULL,
    amount DOUBLE PRECISION NOT NULL,
    fee DOUBLE PRECISION NOT NULL DEFAULT 0.0,
    fee_currency VARCHAR(16) NOT NULL DEFAULT 'USDT',
    time TIMESTAMPTZ NOT NULL,
    is_matched BOOLEAN DEFAULT FALSE,
    remaining_amount DOUBLE PRECISION NOT NULL,
    notes TEXT DEFAULT '',
    UNIQUE (exchange, trade_id)
);

CREATE INDEX IF NOT EXISTS idx_account_trades_lookup 
ON account_trades (exchange, symbol, time DESC);

-- 6. Tabla de Salidas y Gastos (Withdrawals / Consumos)
CREATE TABLE IF NOT EXISTS account_withdrawals (
    id BIGSERIAL PRIMARY KEY,
    exchange VARCHAR(32) NOT NULL,
    currency VARCHAR(16) NOT NULL,
    amount DOUBLE PRECISION NOT NULL,
    fee DOUBLE PRECISION NOT NULL DEFAULT 0.0,
    time TIMESTAMPTZ NOT NULL,
    category VARCHAR(64) DEFAULT 'Gasto Personal',
    description TEXT,
    tx_id VARCHAR(128),
    is_matched BOOLEAN DEFAULT FALSE,
    UNIQUE (exchange, tx_id, time)
);

CREATE INDEX IF NOT EXISTS idx_withdrawals_lookup 
ON account_withdrawals (exchange, currency, time DESC);

-- 7. Tabla de Casamientos (Matches / PnL)
CREATE TABLE IF NOT EXISTS trade_matches (
    id BIGSERIAL PRIMARY KEY,
    buy_trade_id BIGINT REFERENCES account_trades(id) ON DELETE CASCADE,
    sell_trade_id BIGINT DEFAULT NULL,
    withdrawal_id BIGINT REFERENCES account_withdrawals(id) ON DELETE SET NULL,
    match_type VARCHAR(16) DEFAULT 'trade', -- 'trade' o 'expense'
    matched_amount DOUBLE PRECISION NOT NULL,
    profit DOUBLE PRECISION NOT NULL DEFAULT 0.0,
    time TIMESTAMPTZ NOT NULL,
    notes TEXT DEFAULT ''
);

CREATE INDEX IF NOT EXISTS idx_matches_trades ON trade_matches (buy_trade_id, sell_trade_id);
CREATE INDEX IF NOT EXISTS idx_matches_time ON trade_matches (time DESC);

-- 8. Tabla de Estado y Latido del Colector 24/7 (Heartbeat)
CREATE TABLE IF NOT EXISTS system_heartbeat (
    service_name VARCHAR(32) PRIMARY KEY,
    last_heartbeat TIMESTAMPTZ NOT NULL,
    status VARCHAR(32) DEFAULT 'running',
    details JSONB DEFAULT '{}'::jsonb
);

-- 9. Tablas del Motor Multi-Bot (Flota CriptoBot en PostgreSQL)
CREATE TABLE IF NOT EXISTS bots (
    bot_id VARCHAR(64) PRIMARY KEY,
    symbol VARCHAR(32) NOT NULL,
    strategy_name VARCHAR(64) NOT NULL,
    budget DOUBLE PRECISION NOT NULL,
    status VARCHAR(32) NOT NULL,
    dry_run BOOLEAN NOT NULL DEFAULT TRUE,
    config_json TEXT NOT NULL,
    created_at BIGINT NOT NULL,
    updated_at BIGINT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_bots_status ON bots (status);

CREATE TABLE IF NOT EXISTS orders (
    id VARCHAR(64) PRIMARY KEY,
    bot_id VARCHAR(64) NOT NULL,
    symbol VARCHAR(32) NOT NULL,
    side VARCHAR(16) NOT NULL,
    order_type VARCHAR(16) NOT NULL,
    price DOUBLE PRECISION NOT NULL,
    amount DOUBLE PRECISION NOT NULL,
    status VARCHAR(32) NOT NULL,
    fee DOUBLE PRECISION DEFAULT 0.0,
    created_at BIGINT NOT NULL,
    filled_at BIGINT
);

CREATE INDEX IF NOT EXISTS idx_orders_bot_status ON orders (bot_id, status);

CREATE TABLE IF NOT EXISTS tranches (
    id SERIAL PRIMARY KEY,
    bot_id VARCHAR(64) NOT NULL,
    symbol VARCHAR(32) NOT NULL,
    tranche_index INTEGER NOT NULL,
    allocated_budget DOUBLE PRECISION NOT NULL,
    buy_price DOUBLE PRECISION NOT NULL,
    amount DOUBLE PRECISION NOT NULL,
    target_sell_price DOUBLE PRECISION NOT NULL,
    highest_price DOUBLE PRECISION DEFAULT 0.0,
    actual_sell_price DOUBLE PRECISION,
    status VARCHAR(32) NOT NULL,
    buy_fee DOUBLE PRECISION DEFAULT 0.0,
    sell_fee DOUBLE PRECISION DEFAULT 0.0,
    buy_timestamp BIGINT,
    sell_timestamp BIGINT,
    profit_usdt DOUBLE PRECISION DEFAULT 0.0,
    subsidized_satoshis DOUBLE PRECISION DEFAULT 0.0
);

CREATE INDEX IF NOT EXISTS idx_tranches_lookup ON tranches (bot_id, status);

CREATE TABLE IF NOT EXISTS capital_transactions (
    id SERIAL PRIMARY KEY,
    bot_id VARCHAR(64) NOT NULL,
    type VARCHAR(32) NOT NULL,
    amount DOUBLE PRECISION NOT NULL,
    available_after DOUBLE PRECISION NOT NULL,
    timestamp BIGINT NOT NULL,
    reason TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_capital_tx_lookup ON capital_transactions (bot_id, timestamp ASC);

CREATE TABLE IF NOT EXISTS bot_events (
    id SERIAL PRIMARY KEY,
    bot_id VARCHAR(64) NOT NULL,
    event_type VARCHAR(64) NOT NULL,
    details TEXT,
    timestamp BIGINT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_bot_events_lookup ON bot_events (bot_id, timestamp DESC);

CREATE TABLE IF NOT EXISTS system_settings (
    key VARCHAR(64) PRIMARY KEY,
    value_json TEXT NOT NULL,
    updated_at BIGINT NOT NULL
);

CREATE TABLE IF NOT EXISTS strategy_configs (
    id VARCHAR(64) PRIMARY KEY,
    strategy_name VARCHAR(64) NOT NULL,
    name VARCHAR(128) NOT NULL,
    description TEXT,
    is_recommended BOOLEAN NOT NULL DEFAULT FALSE,
    is_system BOOLEAN NOT NULL DEFAULT FALSE,
    params_json TEXT NOT NULL,
    created_at BIGINT NOT NULL,
    updated_at BIGINT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_strategy_configs_strategy ON strategy_configs (strategy_name);

