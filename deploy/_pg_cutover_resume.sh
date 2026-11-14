#!/usr/bin/env bash
# Resume Postgres cutover after aborted pip. Run as root on ECS.
set -euo pipefail

API=/opt/acquireenglish/services/api
VENV="$API/.venv"
ENVF="$API/.env"
SQLITE_LIVE="$API/acquire_english.db"
SQLITE_BAK=/opt/acquireenglish/backups/acquire_english_20261114_235914.db
PASS_FILE=/root/.acquireenglish_pg_pass
MIGRATE=/tmp/migrate_sqlite_to_postgres.py

if [[ ! -f "$PASS_FILE" ]]; then
  echo "FATAL: missing $PASS_FILE" >&2
  exit 1
fi
PG_PASS=$(tr -d '\r\n' < "$PASS_FILE")
PG_URL_ASYNC="postgresql+asyncpg://acquireenglish:${PG_PASS}@127.0.0.1:5432/acquireenglish"
# migrate script accepts postgresql+psycopg / asyncpg / psycopg2 URL shapes
PG_URL_SYNC="postgresql+psycopg://acquireenglish:${PG_PASS}@127.0.0.1:5432/acquireenglish"
SQLITE_SRC="$SQLITE_LIVE"
[[ -f "$SQLITE_SRC" ]] || SQLITE_SRC="$SQLITE_BAK"
echo "DATABASE_URL shape: postgresql+asyncpg://acquireenglish:***@127.0.0.1:5432/acquireenglish"
echo "sqlite source: $SQLITE_SRC"

echo "==> install drivers (asyncpg 0.31+ has py3.14 wheels; psycopg3 for migrate)"
"$VENV/bin/pip" install --disable-pip-version-check -q 'asyncpg>=0.31.0' 'psycopg[binary]>=3.2'
"$VENV/bin/python" -c "import asyncpg, psycopg; print('asyncpg', asyncpg.__version__, 'psycopg', psycopg.__version__)"

echo "==> create tables via SQLAlchemy"
cd "$API"
export PYTHONPATH="$API"
DATABASE_URL="$PG_URL_ASYNC" "$VENV/bin/python" - <<'PY'
import asyncio, os
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
if [[ ! -f "$MIGRATE" ]]; then
  echo "FATAL: missing $MIGRATE" >&2
  exit 1
fi
sed -i 's/\r$//' "$MIGRATE"
"$VENV/bin/python" "$MIGRATE" --sqlite "$SQLITE_SRC" --pg-url "$PG_URL_SYNC" --wipe

echo "==> verify PG counts"
sudo -u postgres psql -d acquireenglish -c \
  "SELECT 'users' t, count(*)::int c FROM users
   UNION ALL SELECT 'lesson_progress', count(*)::int FROM lesson_progress
   UNION ALL SELECT 'vocab_items', count(*)::int FROM vocab_items
   UNION ALL SELECT 'user_preferences', count(*)::int FROM user_preferences
   UNION ALL SELECT 'user_link_courses', count(*)::int FROM user_link_courses;"

echo "==> switch DATABASE_URL in .env"
cp -a "$ENVF" "/opt/acquireenglish/backups/api_env_before_pg_$(date +%Y%m%d_%H%M%S).env"
python3 - <<PY
from pathlib import Path
p = Path("$ENVF")
url = """$PG_URL_ASYNC"""
lines = [ln for ln in p.read_text(encoding="utf-8").splitlines() if not ln.startswith("DATABASE_URL=")]
lines.append("DATABASE_URL=" + url)
p.write_text("\n".join(lines).rstrip() + "\n", encoding="utf-8")
print("env updated")
PY
grep '^DATABASE_URL=' "$ENVF" | sed -E 's#(postgresql\+asyncpg://[^:]+:)[^@]+@#\1***@#'

echo "==> restart API"
systemctl restart acquireenglish-api
sleep 2
systemctl is-active acquireenglish-api
curl -fsS http://127.0.0.1:5200/api/health; echo
sudo -u postgres psql -d acquireenglish -c '\dt'
echo "CUTOVER_RESUME_OK"
