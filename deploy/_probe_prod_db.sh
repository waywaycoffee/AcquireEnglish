#!/bin/bash
set -euo pipefail
ENV=/opt/acquireenglish/services/api/.env
echo "== DATABASE_URL (masked) =="
grep -E '^DATABASE_URL=' "$ENV" | sed -E 's#(postgresql(\+asyncpg)?://[^:]+:)[^@]+@#\1***@#; s#sqlite\+aiosqlite:///.*#sqlite+aiosqlite:///./acquire_english.db#'
echo "== other env keys (names only) =="
grep -E '^[A-Z_]+=' "$ENV" | cut -d= -f1 | sort
echo "== postgres dbs =="
sudo -u postgres psql -c '\l' 2>/dev/null | head -40 || true
echo "== postgres roles =="
sudo -u postgres psql -c '\du' 2>/dev/null | head -40 || true
echo "== sqlite file =="
DB=/opt/acquireenglish/services/api/acquire_english.db
ls -la "$DB" 2>/dev/null || echo "no sqlite db"
if [[ -f "$DB" ]]; then
  python3 - <<'PY'
import sqlite3
c=sqlite3.connect("/opt/acquireenglish/services/api/acquire_english.db")
tables=[t[0] for t in c.execute("SELECT name FROM sqlite_master WHERE type='table'").fetchall()]
print("tables:", tables)
for t in tables:
    try:
        n=c.execute(f"SELECT COUNT(*) FROM [{t}]").fetchone()[0]
        print(f"  {t}: {n}")
    except Exception as e:
        print(f"  {t}: err {e}")
PY
fi
echo "== api health =="
curl -fsS http://127.0.0.1:5200/api/health
echo
echo "== asyncpg installed? =="
/opt/acquireenglish/services/api/.venv/bin/python -c "import asyncpg; print(asyncpg.__version__)" 2>&1 || echo "asyncpg missing"
