#!/usr/bin/env bash
set -euo pipefail
cat /opt/acquireenglish/deploy/acquireenglish-api.service
echo "===="
cp /opt/acquireenglish/deploy/acquireenglish-api.service /etc/systemd/system/acquireenglish-api.service
systemctl daemon-reload
systemctl reset-failed acquireenglish-api || true
systemctl restart acquireenglish-api
sleep 1
systemctl is-active acquireenglish-api
systemctl --no-pager -l status acquireenglish-api | head -25
curl -fsS http://127.0.0.1:5200/api/health
echo
curl -fsS https://acquireenglish.curlhairai.com/api/health
echo
curl -fsS -o /dev/null -w "web=%{http_code}\n" https://acquireenglish.curlhairai.com/
ls -la /opt/acquireenglish/www
python3 - <<'PY'
import json, urllib.request
d = json.load(urllib.request.urlopen("http://127.0.0.1:5200/openapi.json"))
ps = sorted(d["paths"])
print("paths", len(ps))
print("\n".join(ps))
PY
