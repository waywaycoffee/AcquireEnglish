#!/usr/bin/env bash
set -euo pipefail
cd /opt/acquireenglish/services/api
# shellcheck disable=SC1091
source .venv/bin/activate
python -c 'from app.main import app; print("app_ok", len(app.routes))'
python - <<'PY'
from pathlib import Path
import importlib.metadata as md
req = Path("requirements.txt").read_text().splitlines()
bad = []
for line in req:
    line = line.strip()
    if not line or line.startswith("#"):
        continue
    name = line.split("==")[0].split("[")[0]
    want = line.split("==")[1] if "==" in line else None
    try:
        got = md.version(name)
    except Exception as e:
        bad.append(f"{line} MISSING {e}")
        continue
    if want and got != want:
        bad.append(f"{name}: want {want} got {got}")
print("req_pin_ok" if not bad else "\n".join(bad))
PY
command -v ffmpeg >/dev/null && ffmpeg -version | head -n1 || echo ffmpeg=MISSING
nginx -v 2>&1 || true
systemctl is-active acquireenglish-api
systemctl is-active nginx
ss -lntp | grep -E '5200|8770|8001' || true
curl -fsS http://127.0.0.1:5200/api/health; echo
curl -fsS -o /dev/null -w "coach=%{http_code}\n" https://acquireenglish.curlhairai.com/coach/ || true
ps -ef | grep -E 'oral_coach|uvicorn' | grep -v grep || true
