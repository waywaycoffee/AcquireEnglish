#!/usr/bin/env bash
set -euo pipefail
API=/opt/acquireenglish/services/api
echo "=== PROD API VENV ==="
"$API/.venv/bin/python" --version
"$API/.venv/bin/pip" check || true
"$API/.venv/bin/python" - <<'PY'
import importlib
mods = [
    "fastapi","uvicorn","pydantic","pydantic_settings","email_validator",
    "jose","passlib","bcrypt","sqlalchemy","aiosqlite","greenlet","multipart","httpx",
]
missing=[]
for m in mods:
    name = m
    try:
        importlib.import_module(name)
    except Exception as e:
        missing.append(f"{m}:{e}")
print("missing", missing or "none")
from app.main import app
print("app_ok routes", len(app.routes))
PY
echo "=== SYSTEM BINS ==="
command -v ffmpeg >/dev/null && ffmpeg -version | head -n1 || echo "ffmpeg=MISSING"
command -v nginx >/dev/null && nginx -v 2>&1 || echo "nginx=MISSING"
systemctl is-active acquireenglish-api
systemctl is-active nginx
echo "=== OPTIONAL SIDECARS ==="
ss -lntp | grep -E '5200|8770|8001' || true
curl -fsS http://127.0.0.1:5200/api/health; echo
curl -fsS -o /dev/null -w "coach=%{http_code}\n" https://acquireenglish.curlhairai.com/coach/ || true
echo "=== REQUIREMENTS PIN CHECK ==="
"$API/.venv/bin/python" - <<'PY'
from pathlib import Path
import pkg_resources
req = Path("/opt/acquireenglish/services/api/requirements.txt").read_text().splitlines()
bad=[]
for line in req:
    line=line.strip()
    if not line or line.startswith("#"):
        continue
    try:
        pkg_resources.require(line)
    except Exception as e:
        bad.append(f"{line} -> {e}")
print("req_ok" if not bad else "\n".join(bad))
PY
