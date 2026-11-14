#!/bin/bash
set -euo pipefail
exec > >(tee -a /tmp/pg_cutover_finish2.log) 2>&1

API_DIR=/opt/acquireenglish/services/api
ENV_FILE="$API_DIR/.env"
DB_FILE="$API_DIR/acquire_english.db"
BACKUP_DIR=/opt/acquireenglish/backups
TS=$(date +%Y%m%d_%H%M%S)
PG_USER=acquireenglish
PG_DB=acquireenglish
PG_PASS=$(cat /root/.acquireenglish_pg_pass)
PG_URL_ASYNC="postgresql+asyncpg://${PG_USER}:${PG_PASS}@127.0.0.1:5432/${PG_DB}"
PG_URL_SYNC="postgresql://${PG_USER}:${PG_PASS}@127.0.0.1:5432/${PG_DB}"

echo "START ${TS}"
echo "DATABASE_URL shape: postgresql+asyncpg://${PG_USER}:***@127.0.0.1:5432/${PG_DB}"

cd "$API_DIR"
.venv/bin/python -c "import asyncpg; print('asyncpg', asyncpg.__version__)"

echo "==> install psycopg binary"
.venv/bin/pip install --disable-pip-version-check 'psycopg[binary]'
.venv/bin/python -c "import psycopg; print('psycopg', psycopg.__version__)"

# Point settings at PG for create_all without mutating .env yet
echo "==> create_all"
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

echo "==> migrate sqlite -> pg"
.venv/bin/python - <<PY
import sqlite3
from urllib.parse import urlparse, unquote
import psycopg

sqlite_path = "$DB_FILE"
pg_url = "$PG_URL_SYNC"
tables = ["users", "lesson_progress", "vocab_items", "user_preferences", "user_link_courses"]
src = sqlite3.connect(sqlite_path)
src.row_factory = sqlite3.Row
parsed = urlparse(pg_url)
conninfo = dict(
    dbname=(parsed.path or "/").lstrip("/") or "acquireenglish",
    user=unquote(parsed.username or ""),
    password=unquote(parsed.password or ""),
    host=parsed.hostname or "127.0.0.1",
    port=parsed.port or 5432,
)
summary = {}
with psycopg.connect(**conninfo) as dst:
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

echo "==> PG counts"
sudo -u postgres psql -d "$PG_DB" -c "SELECT 'users' t, count(*) FROM users UNION ALL SELECT 'prefs', count(*) FROM user_preferences UNION ALL SELECT 'progress', count(*) FROM lesson_progress UNION ALL SELECT 'vocab', count(*) FROM vocab_items UNION ALL SELECT 'links', count(*) FROM user_link_courses;"

mkdir -p "$BACKUP_DIR"
cp -a "$ENV_FILE" "$BACKUP_DIR/api_env_${TS}.env"
cp -a "$DB_FILE" "$BACKUP_DIR/acquire_english_${TS}.db" 2>/dev/null || true

echo "==> update .env DATABASE_URL"
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
echo "CUTOVER_OK ${TS}"
