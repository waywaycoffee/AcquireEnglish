#!/bin/bash
# Run ON the ECS host as root. Idempotent Postgres cutover for AcquireEnglish API.
set -euo pipefail

API_DIR=/opt/acquireenglish/services/api
ENV_FILE="$API_DIR/.env"
DB_FILE="$API_DIR/acquire_english.db"
BACKUP_DIR=/opt/acquireenglish/backups
TS=$(date +%Y%m%d_%H%M%S)
PG_USER=acquireenglish
PG_DB=acquireenglish
PG_PASS_FILE=/root/.acquireenglish_pg_pass

echo "==> backup sqlite"
mkdir -p "$BACKUP_DIR"
if [[ -f "$DB_FILE" ]]; then
  cp -a "$DB_FILE" "$BACKUP_DIR/acquire_english_${TS}.db"
  ls -la "$BACKUP_DIR/acquire_english_${TS}.db"
else
  echo "WARN: no sqlite file at $DB_FILE"
fi

echo "==> ensure postgresql packages"
export DEBIAN_FRONTEND=noninteractive
if ! command -v psql >/dev/null; then
  apt-get update -qq
  apt-get install -y -qq postgresql postgresql-contrib
fi
systemctl enable --now postgresql
systemctl is-active postgresql

echo "==> create role/db if missing"
if [[ -f "$PG_PASS_FILE" ]]; then
  PG_PASS=$(cat "$PG_PASS_FILE")
else
  PG_PASS=$(openssl rand -base64 24 | tr -d '/+=' | head -c 32)
  umask 077
  printf '%s' "$PG_PASS" > "$PG_PASS_FILE"
  chmod 600 "$PG_PASS_FILE"
fi

sudo -u postgres psql -v ON_ERROR_STOP=1 <<SQL
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '${PG_USER}') THEN
    CREATE ROLE ${PG_USER} LOGIN PASSWORD '${PG_PASS}';
  ELSE
    ALTER ROLE ${PG_USER} WITH LOGIN PASSWORD '${PG_PASS}';
  END IF;
END
\$\$;
SELECT 'role_ok' AS status;
SQL

sudo -u postgres psql -v ON_ERROR_STOP=1 -tc "SELECT 1 FROM pg_database WHERE datname='${PG_DB}'" | grep -q 1 \
  || sudo -u postgres psql -v ON_ERROR_STOP=1 -c "CREATE DATABASE ${PG_DB} OWNER ${PG_USER};"

sudo -u postgres psql -v ON_ERROR_STOP=1 -c "GRANT ALL PRIVILEGES ON DATABASE ${PG_DB} TO ${PG_USER};"
# PG15+ schema privileges
sudo -u postgres psql -v ON_ERROR_STOP=1 -d "$PG_DB" -c "GRANT ALL ON SCHEMA public TO ${PG_USER};"
sudo -u postgres psql -v ON_ERROR_STOP=1 -d "$PG_DB" -c "ALTER SCHEMA public OWNER TO ${PG_USER};" || true

PG_URL_ASYNC="postgresql+asyncpg://${PG_USER}:${PG_PASS}@127.0.0.1:5432/${PG_DB}"
PG_URL_SYNC="postgresql+psycopg2://${PG_USER}:${PG_PASS}@127.0.0.1:5432/${PG_DB}"
echo "DATABASE_URL shape: postgresql+asyncpg://${PG_USER}:***@127.0.0.1:5432/${PG_DB}"

echo "==> install python drivers in API venv"
cd "$API_DIR"
.venv/bin/pip install -q 'asyncpg==0.30.0' 'psycopg2-binary==2.9.10'

echo "==> create tables via SQLAlchemy create_all (asyncpg)"
.venv/bin/python - <<PY
import asyncio
import os
os.environ["DATABASE_URL"] = """${PG_URL_ASYNC}"""
from app.database import Base, engine
import app.models  # noqa: F401
from app.db_migrate import ensure_schema_columns

async def main():
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
        await ensure_schema_columns(conn)
    await engine.dispose()
    print("create_all ok")

asyncio.run(main())
PY

echo "==> migrate sqlite -> postgres"
if [[ -f /tmp/migrate_sqlite_to_postgres.py && -f "$DB_FILE" ]]; then
  .venv/bin/python /tmp/migrate_sqlite_to_postgres.py \
    --sqlite "$DB_FILE" \
    --pg-url "$PG_URL_SYNC" \
    --wipe
else
  echo "WARN: skip data migrate (missing script or sqlite)"
fi

echo "==> verify PG row counts"
sudo -u postgres psql -d "$PG_DB" -c "SELECT 'users' t, count(*) FROM users UNION ALL SELECT 'lesson_progress', count(*) FROM lesson_progress UNION ALL SELECT 'vocab_items', count(*) FROM vocab_items UNION ALL SELECT 'user_preferences', count(*) FROM user_preferences UNION ALL SELECT 'user_link_courses', count(*) FROM user_link_courses;"

echo "==> switch DATABASE_URL in .env (backup first)"
cp -a "$ENV_FILE" "$BACKUP_DIR/api_env_${TS}.env"
python3 - <<PY
from pathlib import Path
p = Path("$ENV_FILE")
lines = p.read_text(encoding="utf-8").splitlines()
out = []
found = False
new_url = "postgresql+asyncpg://${PG_USER}:${PG_PASS}@127.0.0.1:5432/${PG_DB}"
for ln in lines:
    if ln.startswith("DATABASE_URL="):
        out.append("DATABASE_URL=" + new_url)
        found = True
    else:
        out.append(ln)
if not found:
    out.append("DATABASE_URL=" + new_url)
p.write_text("\\n".join(out).rstrip() + "\\n", encoding="utf-8")
print("env DATABASE_URL updated (password not printed)")
PY

# mask check
grep '^DATABASE_URL=' "$ENV_FILE" | sed -E 's#(postgresql\+asyncpg://[^:]+:)[^@]+@#\1***@#'

echo "==> restart API"
systemctl restart acquireenglish-api
sleep 2
systemctl is-active acquireenglish-api
curl -fsS http://127.0.0.1:5200/api/health
echo

echo "==> post-switch PG counts again"
sudo -u postgres psql -d "$PG_DB" -c "SELECT count(*) AS users FROM users;"
echo "CUTOVER_OK ${TS}"
