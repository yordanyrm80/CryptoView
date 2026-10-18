# apex-quant: Institutional Multi-Regime Quantitative Trading Platform

High-performance quantitative algorithmic trading and backtesting platform built in Python 3.12 with Flutter multiplatform telemetry for the **KuCoin Spot** market, empirically optimized over **9 full years of real historical data (2017–2026, 77,514 BTC/USDT 1h candles)**.

The core mathematical objective of the platform is **long-term compound return maximization and massive cash flow realization ($EV > 0$)**, without sacrificing net profitability to artificially smooth floating drawdown. Designed to scale into a multi-bot, multi-asset algorithmic fleet.

---

## 1. Validated Engines & Strategies

| Asset | Assigned Strategy | Code File | Key Quantitative Features | 9-Year Historical Performance |
| :--- | :--- | :--- | :--- | :---: |
| **BTC/USDT** | `BtcQuantumCompoundRegimeStrategy` | [`src/strategies/btc_quantum_compound_regime.py`](src/strategies/btc_quantum_compound_regime.py) | • Front-Loaded Weights `[0.30, 0.25, 0.20, 0.15, 0.10]`<br>• Cascading Subsidized Recycling (35% cut, up to -12% floor)<br>• Panic Sniper ($RSI < 28$, TP +7%)<br>• Trailing Stop (2.0%) in trend<br>• Macro Multi-TF Daily EMA 200 (4,800h) | **+1,995.09% (\$20,950.86 USDT)**<br>+\$19,260.59 USDT cash extracted<br>2018 Crash: -14.90% vs -78.5% B&H |
| **BTC/USDT** | `BtcQuantumEvolutionRegimeStrategy` | [`src/strategies/btc_quantum_evolution_regime.py`](src/strategies/btc_quantum_evolution_regime.py) | • Autonomous Floor Tranches (T5..T7)<br>• 70% Trend Weight & 1.4% Trailing Stop<br>• Autonomous secular bear rescue mechanism | **+2,189.75% (\$22,897.56 USDT)**<br>High Sharpe (2.19 in bull phases) |
| **ETH/USDT** | `AdaptiveThreeRegimeStrategy` | [`src/strategies/three_regime.py`](src/strategies/three_regime.py) | • Compact anchored grid ($1.0\times, 2.2\times, 4.0\times, 6.5\times$ ATR)<br>• Take Profit at +10.0%<br>• Liquid USDT retention | **+223.31%** (143 trades, 98.6% WR) |
| **LTC/USDT** | `AdaptiveThreeRegimeStrategy` | [`src/strategies/three_regime.py`](src/strategies/three_regime.py) | • Fast mean-reversion grid<br>• Take Profit at +10.0% | **+29.22%** (75 trades, 97.3% WR) |

---

## 2. Project Architecture

```
apex-quant/
├── CONTEXTO.md                    # Master Architecture & Single Source of Truth
├── GEMINI.md                      # Workspace Technical & Language Standards
├── README.md                      # Platform overview and quickstart guide
├── pytest.ini                     # Automated test configuration
├── requirements.txt               # Pinned dependencies (Python 3.12)
├── criptobot_ui/                  # Multiplatform Flutter Frontend (Mobile, Web, Desktop)
├── data/
│   └── .gitkeep                   # Directory placeholder
├── docs/
│   └── MANUAL_OPERATIVO_HIBRIDO.md# Operational manual & hybrid spot playbooks
├── scripts/                       # Simulation runners and research benchmarks
│   ├── compare_quantum_vs_satoshi.py
│   ├── compare_ultra_vs_quantum.py
│   ├── run_simulation.py
│   └── simulate_bottom_reload_synergy.py
├── src/
│   ├── api/                       # FastAPI Backend, WebSockets, Pydantic schemas, and routes
│   ├── core/                      # Live runner and Market Regime Detector
│   ├── domain/                    # Canonical domain models (BotConfig, Tranche, Order, Candle)
│   ├── exchange/                  # KuCoin CCXT asynchronous exchange client
│   ├── indicators/                # Vectorized indicator calculations (EMA, ATR, RSI, ADX, Donchian)
│   ├── simulation/                # Backtesting engine with cascading subsidies and metrics
│   ├── storage/                   # PostgreSQL repositories (candles, tranches, capital audit)
│   └── strategies/                # Modular quantitative strategy implementations
└── tests/                         # Full automated pytest test suite (43 passing tests)
```

---

## 3. Quickstart Guide

### Development Environment (Python 3.12)
```bash
# Activate virtual environment (Windows PowerShell)
.venv\Scripts\activate

# Activate virtual environment (Linux VPS)
source .venv/bin/activate
```

### Run Full Test Suite
```bash
pytest -v
# Output: 38 passed in ~2.3s
```

### Start Backend API for Flutter UI (FastAPI + Uvicorn)
```bash
# Local development mode:
uvicorn src.api.app:app --host 127.0.0.1 --port 8000 --reload

# Production mode on VPS (isolated via Tailscale Mesh VPN interface):
uvicorn src.api.app:app --host 100.x.y.z --port 8000 --workers 2
```

### Run Multicycle Research Benchmark
```bash
python scripts/compare_ultra_vs_quantum.py
```

---

## 4. Specialized Documentation

- **Master System Context:** [`CONTEXTO.md`](CONTEXTO.md)  
- **Operational Manual:** [`docs/MANUAL_OPERATIVO_HIBRIDO.md`](docs/MANUAL_OPERATIVO_HIBRIDO.md)  
