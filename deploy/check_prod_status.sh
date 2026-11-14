#!/usr/bin/env bash
set -euo pipefail
echo "== openapi paths =="
python3 - <<'PY'
import json, urllib.request
d = json.load(urllib.request.urlopen("http://127.0.0.1:5200/openapi.json"))
ps = sorted(d.get("paths", {}))
print(len(ps))
print("\n".join(ps))
PY
echo "== env =="
python3 - <<'PY'
from pathlib import Path
text = Path("/opt/acquireenglish/services/api/.env").read_text(encoding="utf-8", errors="ignore")
keys = [
    "DASHSCOPE_API_KEY",
    "BILIBILI_COOKIE",
    "LIVEKIT_URL",
    "LIVEKIT_API_KEY",
    "LIVEKIT_API_SECRET",
    "WECHAT_APP_ID",
    "AUTH_SMS_MOCK",
    "AUTH_WECHAT_MOCK",
    "MEDIA_PUBLIC_BASE",
    "SECRET_KEY",
]
for k in keys:
    found = False
    for line in text.splitlines():
        if line.startswith(k + "="):
            v = line.split("=", 1)[1].strip()
            if not v:
                state = "EMPTY"
            elif "change-me" in v.lower() or v.startswith("local-dev"):
                state = "PLACEHOLDER"
            else:
                state = "SET"
            print(f"{k}={state}")
            found = True
            break
    if not found:
        print(f"{k}=MISSING")
PY
echo "== endpoints =="
curl -sS -o /dev/null -w "web=%{http_code}\n" --max-time 8 https://acquireenglish.curlhairai.com/
curl -sS -o /dev/null -w "coach=%{http_code}\n" --max-time 8 https://acquireenglish.curlhairai.com/coach/ || true
curl -sS -o /dev/null -w "livekit_status=%{http_code}\n" --max-time 8 https://acquireenglish.curlhairai.com/api/livekit/status || true
echo "== files =="
ls -la /opt/acquireenglish/www | head
ls -la /opt/acquireenglish/services/api/app/main.py
systemctl is-active nginx
test -d /opt/acquireenglish/.git && git -C /opt/acquireenglish rev-parse --short HEAD || echo no-git-on-server
