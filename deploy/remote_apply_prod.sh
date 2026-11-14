#!/usr/bin/env bash
set -euo pipefail

API=/opt/acquireenglish/services/api
WWW=/opt/acquireenglish/www

mkdir -p "$API/app" "$WWW" /opt/acquireenglish/media /opt/acquireenglish/data

# Extract while preserving remote .env / db / venv
rm -rf /tmp/ae_unpack_$$
mkdir -p /tmp/ae_unpack_$$
tar -xzf /tmp/ae_prod_deploy.tar.gz -C /tmp/ae_unpack_$$

# Sync API app code
rm -rf "$API/app"
mkdir -p "$API"
cp -a /tmp/ae_unpack_$$/services/api/app "$API/app"
cp -a /tmp/ae_unpack_$$/services/api/requirements.txt "$API/requirements.txt"
if [ -d /tmp/ae_unpack_$$/services/api/deploy ]; then
  mkdir -p "$API/deploy"
  cp -a /tmp/ae_unpack_$$/services/api/deploy/. "$API/deploy/"
fi

# Replace web static
rm -rf "$WWW"/*
cp -a /tmp/ae_unpack_$$/www/. "$WWW/"

# Ensure AUTH/LIVEKIT keys exist in .env without wiping secrets
python3 - <<'PY'
from pathlib import Path
p = Path("/opt/acquireenglish/services/api/.env")
text = p.read_text(encoding="utf-8") if p.exists() else ""
extras = {
    "AUTH_SMS_MOCK": "true",
    "AUTH_SMS_MOCK_CODE": "123456",
    "AUTH_SMS_CODE_TTL_SECONDS": "300",
    "AUTH_WECHAT_MOCK": "true",
    "LIVEKIT_URL": "",
    "LIVEKIT_API_KEY": "",
    "LIVEKIT_API_SECRET": "",
    "MEDIA_PUBLIC_BASE": "https://acquireenglish.curlhairai.com",
}
lines = text.splitlines()
keys = {ln.split("=", 1)[0] for ln in lines if "=" in ln and not ln.strip().startswith("#")}
out = list(lines)
for k, v in extras.items():
    if k not in keys:
        out.append(f"{k}={v}")
p.parent.mkdir(parents=True, exist_ok=True)
p.write_text("\n".join(out).rstrip() + "\n", encoding="utf-8")
print("env ok", p)
PY

# Import smoke (no pip; py3.14 venv fragile)
cd "$API"
# shellcheck disable=SC1091
source .venv/bin/activate
python - <<'PY'
from app.main import app
print("app_ok", app.title, "routes", len(app.routes))
PY

# Prefer the known-good ECS unit path/port (:5200 under /opt/acquireenglish)
if [ -f /opt/acquireenglish/deploy/acquireenglish-api.service ]; then
  cp /opt/acquireenglish/deploy/acquireenglish-api.service /etc/systemd/system/acquireenglish-api.service
  systemctl daemon-reload
fi

systemctl restart acquireenglish-api
sleep 1
systemctl is-active acquireenglish-api
curl -fsS http://127.0.0.1:5200/api/health; echo
curl -fsS https://acquireenglish.curlhairai.com/api/health; echo
curl -fsS -o /dev/null -w "web=%{http_code}\n" https://acquireenglish.curlhairai.com/
ls -la "$WWW" | head
python3 - <<'PY'
import json, urllib.request
d = json.load(urllib.request.urlopen("http://127.0.0.1:5200/openapi.json"))
print("paths", len(d.get("paths", {})))
PY

rm -rf /tmp/ae_unpack_$$
echo DONE
