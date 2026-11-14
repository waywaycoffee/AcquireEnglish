#!/bin/bash
set -euo pipefail
exec > >(tee /tmp/pg_reset_and_finish.log) 2>&1
echo "START $(date -Is)"

API_DIR=/opt/acquireenglish/services/api
ENV_FILE="$API_DIR/.env"
DB_FILE="$API_DIR/acquire_english.db"
BACKUP_DIR=/opt/acquireenglish/backups
TS=$(date +%Y%m%d_%H%M%S)
PG_USER=acquireenglish
PG_DB=acquireenglish

# Fresh strong password (alnum only — safe in URLs)
PG_PASS=$(openssl rand -hex 24)
umask 077
printf '%s' "$PG_PASS" > /root/.acquireenglish_pg_pass
chmod 600 /root/.acquireenglish_pg_pass

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
SQL

sudo -u postgres psql -v ON_ERROR_STOP=1 -tc "SELECT 1 FROM pg_database WHERE datname='${PG_DB}'" | grep -q 1 \
  || sudo -u postgres psql -v ON_ERROR_STOP=1 -c "CREATE DATABASE ${PG_DB} OWNER ${PG_USER};"
sudo -u postgres psql -v ON_ERROR_STOP=1 -c "GRANT ALL PRIVILEGES ON DATABASE ${PG_DB} TO ${PG_USER};"
sudo -u postgres psql -v ON_ERROR_STOP=1 -d "$PG_DB" -c "GRANT ALL ON SCHEMA public TO ${PG_USER};"
sudo -u postgres psql -v ON_ERROR_STOP=1 -d "$PG_DB" -c "ALTER SCHEMA public OWNER TO ${PG_USER};" || true

# Ensure password auth for local TCP
if ! grep -q 'acquireenglish' /etc/postgresql/*/main/pg_hba.conf 2>/dev/null; then
  HBA=$(ls /etc/postgresql/*/main/pg_hba.conf | head -1)
  # Insert before first host line if needed — rely on default scram/md5 for 127.0.0.1
  echo "hba=$HBA"
  grep -E '127.0.0.1|scram|md5' "$HBA" | head -5 || true
fi

PG_URL_ASYNC="postgresql+asyncpg://${PG_USER}:${PG_PASS}@127.0.0.1:5432/${PG_DB}"
echo "DATABASE_URL shape: postgresql+asyncpg://${PG_USER}:***@127.0.0.1:5432/${PG_DB}"

# Quick auth probe with psycopg
cd "$API_DIR"
.venv/bin/python - <<PY
import psycopg
conn = psycopg.connect(host="127.0.0.1", port=5432, dbname="${PG_DB}", user="${PG_USER}", password="${PG_PASS}")
conn.execute("SELECT 1")
conn.close()
print("psycopg auth ok")
PY

export DATABASE_URL="$PG_URL_ASYNC"
.venv/bin/python - <<'PY'
import asyncio
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

.venv/bin/python - <<PY
import sqlite3
import psycopg

sqlite_path = "$DB_FILE"
tables = ["users", "lesson_progress", "vocab_items", "user_preferences", "user_link_courses"]
src = sqlite3.connect(sqlite_path)
src.row_factory = sqlite3.Row
summary = {}
with psycopg.connect(host="127.0.0.1", port=5432, dbname="${PG_DB}", user="${PG_USER}", password="${PG_PASS}") as dst:
    with dst.cursor() as cur:
        for table in reversed(tables):
            cur.execute(f'TRUNCATE TABLE "{table}" RESTART IDENTITY CASCADE')
        for table in tables:
            cols = [r[1] for r in src.execute(f"PRAGMA table_info({table})").fetchall()]
            rows = src.execute(f"SELECT * FROM {table}").fetchall()
            if not cols or not rows:
                summary[table] = 0
                continue
            col_list = ", ".join(f'"{c}"' for c in cols)
            placeholders = ", ".join(["%s"] * len(cols))
            sql = f'INSERT INTO "{table}" ({col_list}) VALUES ({placeholders}) ON CONFLICT DO NOTHING'
            payload = [tuple(r[c] for c in cols) for r in rows]
            cur.executemany(sql, payload)
            summary[table] = len(payload)
        for table in tables:
            cur.execute(
                f"""SELECT setval(pg_get_serial_sequence('"{table}"', 'id'),
                    COALESCE((SELECT MAX(id) FROM "{table}"), 1), true)"""
            )
    dst.commit()
print("rows:", summary)
src.close()
PY

sudo -u postgres psql -d "$PG_DB" -c "SELECT 'users' t, count(*) FROM users UNION ALL SELECT 'prefs', count(*) FROM user_preferences UNION ALL SELECT 'progress', count(*) FROM lesson_progress UNION ALL SELECT 'vocab', count(*) FROM vocab_items UNION ALL SELECT 'links', count(*) FROM user_link_courses;"

mkdir -p "$BACKUP_DIR"
cp -a "$ENV_FILE" "$BACKUP_DIR/api_env_${TS}.env"
cp -a "$DB_FILE" "$BACKUP_DIR/acquire_english_${TS}.db" 2>/dev/null || true

python3 - <<PY
from pathlib import Path
p = Path("$ENV_FILE")
lines = p.read_text(encoding="utf-8").splitlines()
new_url = "postgresql+asyncpg://${PG_USER}:${PG_PASS}@127.0.0.1:5432/${PG_DB}"
out, found = [], False
for ln in lines:
    if ln.startswith("DATABASE_URL="):
        out.append("DATABASE_URL=" + new_url); found = True
    else:
        out.append(ln)
if not found:
    out.append("DATABASE_URL=" + new_url)
p.write_text("\n".join(out).rstrip() + "\n", encoding="utf-8")
print("env updated")
PY
grep '^DATABASE_URL=' "$ENV_FILE" | sed -E 's#(postgresql\+asyncpg://[^:]+:)[^@]+@#\1***@#'

systemctl restart acquireenglish-api
sleep 3
systemctl is-active acquireenglish-api
curl -fsS http://127.0.0.1:5200/api/health; echo

python3 - <<'PY'
import json, urllib.request, uuid, subprocess
suffix = uuid.uuid4().hex[:8]
email = f"pgcut_{suffix}@example.com"
password = f"CutPass_{suffix}!"
req = urllib.request.Request(
    "http://127.0.0.1:5200/api/auth/register",
    data=json.dumps({"email": email, "password": password, "display_name": "cut"}).encode(),
    headers={"Content-Type": "application/json"},
    method="POST",
)
with urllib.request.urlopen(req, timeout=30) as resp:
    body = json.loads(resp.read().decode())
print("register_ok", body["user"]["id"], email)
out = subprocess.check_output(
    ["sudo", "-u", "postgres", "psql", "-d", "acquireenglish", "-Atc",
     f"SELECT count(*) FROM users WHERE email='{email.lower()}';"],
    text=True,
).strip()
print("pg_user_rows", out)
assert out == "1", out
# migrated baseline still present
base = subprocess.check_output(
    ["sudo", "-u", "postgres", "psql", "-d", "acquireenglish", "-Atc", "SELECT count(*) FROM users;"],
    text=True,
).strip()
print("pg_users_total", base)
assert int(base) >= 18, base
PY

echo "CUTOVER_OK ${TS}"
