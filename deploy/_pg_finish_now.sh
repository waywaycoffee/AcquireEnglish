#!/usr/bin/env bash
set -euo pipefail
API=/opt/acquireenglish/services/api
VENV="$API/.venv"
ENVF="$API/.env"
PASS_FILE=/root/.acquireenglish_pg_pass
MIGRATE=/tmp/migrate_sqlite_to_postgres.py
SQLITE_SRC="$API/acquire_english.db"
[[ -f "$SQLITE_SRC" ]] || SQLITE_SRC=/opt/acquireenglish/backups/acquire_english_20261114_235914.db

PG_PASS=$(tr -d '\r\n' < "$PASS_FILE")
PG_URL_ASYNC="postgresql+asyncpg://acquireenglish:${PG_PASS}@127.0.0.1:5432/acquireenglish"
PG_URL_SYNC="postgresql+psycopg://acquireenglish:${PG_PASS}@127.0.0.1:5432/acquireenglish"

echo "==> verify asyncpg"
"$VENV/bin/python" -c "import asyncpg; print(asyncpg.__version__)"

echo "==> ensure psycopg3 for migrate (only-binary preferred)"
if ! "$VENV/bin/python" -c "import psycopg" 2>/dev/null; then
  "$VENV/bin/pip" install --disable-pip-version-check --only-binary=:all: 'psycopg[binary]>=3.2' \
    || "$VENV/bin/pip" install --disable-pip-version-check 'psycopg[binary]>=3.2'
fi
"$VENV/bin/python" -c "import psycopg; print('psycopg', psycopg.__version__)"

echo "==> create_all"
cd "$API"
export PYTHONPATH="$API"
# Force engine URL via env for this process (database.py reads settings at import)
DATABASE_URL="$PG_URL_ASYNC" "$VENV/bin/python" - <<'PY'
import asyncio, os
# Re-bind settings after env is set: recreate engine with explicit URL
from sqlalchemy.ext.asyncio import create_async_engine
from app.database import Base
import app.models  # noqa: F401
from app.db_migrate import ensure_schema_columns

url = os.environ["DATABASE_URL"]
engine = create_async_engine(url, echo=False)

async def main():
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
        await ensure_schema_columns(conn)
    await engine.dispose()
    print("create_all ok")

asyncio.run(main())
PY

echo "==> migrate data"
sed -i 's/\r$//' "$MIGRATE"
"$VENV/bin/python" "$MIGRATE" --sqlite "$SQLITE_SRC" --pg-url "$PG_URL_SYNC" --wipe

echo "==> PG counts"
sudo -u postgres psql -d acquireenglish -c \
  "SELECT 'users' t, count(*)::int c FROM users
   UNION ALL SELECT 'lesson_progress', count(*)::int FROM lesson_progress
   UNION ALL SELECT 'vocab_items', count(*)::int FROM vocab_items
   UNION ALL SELECT 'user_preferences', count(*)::int FROM user_preferences
   UNION ALL SELECT 'user_link_courses', count(*)::int FROM user_link_courses;"

echo "==> write .env DATABASE_URL"
cp -a "$ENVF" "/opt/acquireenglish/backups/api_env_before_pg_finish_$(date +%Y%m%d_%H%M%S).env"
python3 - <<PY
from pathlib import Path
p = Path("$ENVF")
url = """$PG_URL_ASYNC"""
lines = [ln for ln in p.read_text(encoding="utf-8").splitlines() if not ln.startswith("DATABASE_URL=")]
lines.append("DATABASE_URL=" + url)
p.write_text("\n".join(lines).rstrip() + "\n", encoding="utf-8")
print("env ok")
PY
grep '^DATABASE_URL=' "$ENVF" | sed -E 's#(postgresql\+asyncpg://[^:]+:)[^@]+@#\1***@#'

echo "==> restart"
systemctl restart acquireenglish-api
sleep 2
systemctl is-active acquireenglish-api
curl -fsS http://127.0.0.1:5200/api/health; echo
# prove new register lands in postgres
EMAIL="pgprove_$(date +%s)@example.com"
TOKEN=$(curl -fsS -X POST http://127.0.0.1:5200/api/auth/register \
  -H 'Content-Type: application/json' \
  -d "{\"email\":\"$EMAIL\",\"password\":\"PgProve_12345!\",\"display_name\":\"PG Prove\"}" \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'][:8]+'…')")
echo "register token prefix: $TOKEN"
sudo -u postgres psql -d acquireenglish -tAc "SELECT email FROM users WHERE email='$EMAIL';"
echo "CUTOVER_FINISH_OK"
