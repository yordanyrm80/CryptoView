#!/usr/bin/env bash
# ==============================================================================
# CriptoBot - Ubuntu 24.04 LTS Tokyo VPS Provisioning Script
# Institutional Zero-Trust Deployment
# ==============================================================================
set -euo pipefail

echo "==> [1/6] Updating Ubuntu packages and installing core runtime..."
sudo apt-get update && sudo apt-get upgrade -y
sudo apt-get install -y python3.12 python3.12-venv python3.12-dev build-essential \
    postgresql postgresql-contrib libpq-dev curl ufw git htop

echo "==> [2/6] Configuring PostgreSQL institutional database..."
sudo systemctl enable postgresql
sudo systemctl start postgresql

sudo -u postgres psql -c "DO \$\$
BEGIN
   IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'cripto') THEN
      CREATE ROLE cripto WITH LOGIN PASSWORD 'cripto_secure_pass';
   END IF;
END
\$\$;"

sudo -u postgres psql -c "SELECT 'CREATE DATABASE criptobot OWNER cripto' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'criptobot')\gexec"

echo "==> [3/6] Setting up application user and directory (/opt/criptobot)..."
if ! id -u cripto >/dev/null 2>&1; then
    sudo useradd -m -s /bin/bash cripto
fi

sudo mkdir -p /opt/criptobot
sudo chown -R cripto:cripto /opt/criptobot

echo "==> [4/6] Creating Python 3.12 Virtual Environment..."
sudo -u cripto python3.12 -m venv /opt/criptobot/.venv
sudo -u cripto /opt/criptobot/.venv/bin/pip install --upgrade pip setuptools wheel
if [ -f /opt/criptobot/requirements.txt ]; then
    sudo -u cripto /opt/criptobot/.venv/bin/pip install -r /opt/criptobot/requirements.txt
fi

echo "==> [5/6] Hardening Firewall (Zero-Trust UFW)..."
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 22/tcp comment 'SSH'
# Notice: Port 8000 is NEVER opened to the public internet!
# Communication happens strictly through the local loopback and Tailscale WireGuard mesh!
sudo ufw --force enable

echo "==> [6/6] Installing systemd service..."
if [ -f /opt/criptobot/deploy/criptobot.service ]; then
    sudo cp /opt/criptobot/deploy/criptobot.service /etc/systemd/system/criptobot.service
    sudo systemctl daemon-reload
    sudo systemctl enable criptobot.service
    echo "CriptoBot systemd service enabled successfully."
fi

echo "=============================================================================="
echo " [✓] VPS PROVISIONING COMPLETED SUCCESSFULLY"
echo " Next steps:"
echo " 1. Setup Tailscale: curl -fsSL https://tailscale.com/install.sh | sh && sudo tailscale up"
echo " 2. Configure /opt/criptobot/.env (chmod 600 /opt/criptobot/.env)"
echo " 3. Start service: sudo systemctl start criptobot"
echo " 4. Check logs: sudo journalctl -u criptobot -f"
echo "=============================================================================="
