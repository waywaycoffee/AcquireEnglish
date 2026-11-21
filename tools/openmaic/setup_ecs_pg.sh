#!/usr/bin/env bash
set -euo pipefail
sudo -u postgres createuser -l openmaic 2>/dev/null || true
sudo -u postgres psql -c "ALTER USER openmaic WITH PASSWORD 'openmaic-dev';"
sudo -u postgres createdb -O openmaic openmaic 2>/dev/null || true
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE openmaic TO openmaic;"
# Postgres 15+: grant schema for migrations
sudo -u postgres psql -d openmaic -c "GRANT ALL ON SCHEMA public TO openmaic;" 2>/dev/null || true
HBA=$(sudo -u postgres psql -tAc "SHOW hba_file")
if ! sudo grep -qE 'openmaic[[:space:]]+openmaic[[:space:]]+100\.' "$HBA"; then
  echo "host openmaic openmaic 100.0.0.0/8 scram-sha-256" | sudo tee -a "$HBA"
  sudo -u postgres psql -c "SELECT pg_reload_conf();"
fi
LISTEN=$(sudo -u postgres psql -tAc "SHOW listen_addresses")
echo "listen_addresses=${LISTEN}"
CONF=$(sudo -u postgres psql -tAc "SHOW config_file")
if [[ "$LISTEN" == "localhost" || "$LISTEN" == "127.0.0.1" ]]; then
  echo "WARN: postgres listens only on localhost; opening SSH tunnel required from GPU box."
  echo "  ssh -N -L 5433:127.0.0.1:5432 acquireenglish"
fi
sudo -u postgres psql -c "\l openmaic"
echo READY
