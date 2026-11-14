#!/usr/bin/env bash
set -euo pipefail
echo "== coach health body =="
curl -fsS http://127.0.0.1:8770/api/health; echo
curl -fsS https://acquireenglish.curlhairai.com/coach/api/health; echo
echo "== coach openapi sample =="
python3 - <<'PY'
import json, urllib.request
d = json.load(urllib.request.urlopen("http://127.0.0.1:8770/openapi.json"))
print(d.get("info"))
print(sorted(d.get("paths", {})))
PY

echo "== ensure dotenv in shared/api venv for oral_coach =="
API_VENV=/opt/acquireenglish/services/api/.venv
if ! "$API_VENV/bin/python" -c 'import dotenv' 2>/dev/null; then
  "$API_VENV/bin/pip" install -q python-dotenv numpy || true
fi
"$API_VENV/bin/python" -c 'import fastapi,uvicorn,dotenv,numpy; print("coach_runtime_imports_ok")'

echo "== soft pin note: keep working newer wheels on py3.14; install only missing runtime deps =="
cd /opt/acquireenglish/services/api
# Do NOT force exact pins on Python 3.14 (pydantic-core rebuild fails).
"$API_VENV/bin/python" - <<'PY'
import importlib
for m in ["fastapi","uvicorn","pydantic","sqlalchemy","aiosqlite","httpx","jose","passlib","multipart","greenlet"]:
    importlib.import_module(m if m != "jose" else "jose")
print("api_runtime_ok")
PY

systemctl restart acquireenglish-oral-coach
sleep 1
systemctl is-active acquireenglish-oral-coach
curl -fsS https://acquireenglish.curlhairai.com/coach/api/health; echo
