#!/usr/bin/env bash
set -euo pipefail
API=/opt/acquireenglish/services/api
VENV=$API/.venv
ENVF=$API/.env
LOG=/tmp/pg_cutover.log
exec > >(tee -a "$LOG") 2>&1
echo "=== $(date -Is) start ==="
"$VENV/bin/pip" install -i https://pypi.tuna.tsinghua.edu.cn/simple asyncpg 'psycopg[binary]'
"$VENV/bin/python" -c 'import asyncpg; print("asyncpg_ok")'
# password
PW_FILE=/opt/acquireenglish/backups/pg_acquireenglish_password.txt
if [[ -f $PW_FILE ]]; then PW=$(cat "$PW_FILE"); else
  PW=$(openssl rand -base64 24 | tr -d '/+=' | head -c 32)
  echo "$PW" > "$PW_FILE"
  chmod 600 "$PW_FILE"
  sudo -u postgres psql -v ON_ERROR_STOP=1 -c "ALTER USER acquireenglish WITH PASSWORD '$PW';" || true
fi
URL="postgresql+asyncpg://acquireenglish:${PW}@127.0.0.1:5432/acquireenglish"
python3 - <<PY
from pathlib import Path
p=Path("$ENVF")
lines=[ln for ln in p.read_text(errors="ignore").splitlines() if not ln.startswith("DATABASE_URL=")]
lines.append("DATABASE_URL=$URL")
p.write_text("\n".join(lines)+"\n")
print("DATABASE_URL set postgresql+asyncpg://acquireenglish:***@127.0.0.1:5432/acquireenglish")
PY
# migrate
if [[ -f /tmp/migrate_sqlite_to_postgres.py ]]; then
  sed -i 's/\r$//' /tmp/migrate_sqlite_to_postgres.py
  cd "$API" && PYTHONPATH="$API" "$VENV/bin/python" /tmp/migrate_sqlite_to_postgres.py
fi
systemctl restart acquireenglish-api
sleep 2
systemctl is-active acquireenglish-api
curl -fsS http://127.0.0.1:5200/api/health; echo
sudo -u postgres psql -d acquireenglish -c '\dt'
echo "=== $(date -Is) done ==="
