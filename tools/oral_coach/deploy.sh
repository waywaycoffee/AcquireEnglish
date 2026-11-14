#!/usr/bin/env bash
# Deploy oral_coach sidecar to Guangzhou ECS behind nginx /coach.
#
# Usage:
#   ./deploy.sh
# Optional:
#   DEPLOY_HOST=root@8.163.45.100
#   DEPLOY_PATH=/opt/acquireenglish/tools/oral_coach
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
HOST="${DEPLOY_HOST:-root@8.163.45.100}"
PATH_REMOTE="${DEPLOY_PATH:-/opt/acquireenglish/tools/oral_coach}"
PUBLIC_BASE="${PUBLIC_API_BASE:-https://acquireenglish.curlhairai.com}"
PORT_LOCAL="${ORAL_COACH_PORT:-8770}"

echo "==> Sync oral_coach to $HOST:$PATH_REMOTE"
ssh "$HOST" "mkdir -p '$PATH_REMOTE/app/providers' '$PATH_REMOTE/scripts' /var/lib/acquire-oral-coach"
rsync -az \
  --exclude '.venv' \
  --exclude '__pycache__' \
  --exclude '.pytest_cache' \
  --exclude '.env' \
  --exclude 'data' \
  "$ROOT/app/" "$HOST:$PATH_REMOTE/app/"
rsync -az \
  "$ROOT/requirements.txt" \
  "$ROOT/run_server.sh" \
  "$ROOT/bootstrap.sh" \
  "$HOST:$PATH_REMOTE/"
if [[ -d "$ROOT/scripts" ]]; then
  rsync -az "$ROOT/scripts/" "$HOST:$PATH_REMOTE/scripts/"
fi

echo "==> Remote bootstrap (venv / env / systemd / nginx)"
ssh "$HOST" \
  PATH_REMOTE="$PATH_REMOTE" \
  PORT_LOCAL="$PORT_LOCAL" \
  bash -s <<'REMOTE'
set -euo pipefail
cd "$PATH_REMOTE"

if [[ ! -f .env ]]; then
  cat > .env <<ENV
ORAL_COACH_HOST=127.0.0.1
ORAL_COACH_PORT=${PORT_LOCAL}
ORAL_COACH_ALLOW_LAN=true
ORAL_COACH_DATA_DIR=/var/lib/acquire-oral-coach
ASR_PROVIDER=mock
PRON_PROVIDER=mock
LLM_PROVIDER=mock
TTS_PROVIDER=mock
AVATAR_PROVIDER=none
ENV
fi

python3 - <<PY
from pathlib import Path
p = Path(".env")
wanted = {
    "ORAL_COACH_HOST": "127.0.0.1",
    "ORAL_COACH_PORT": "${PORT_LOCAL}",
    "ORAL_COACH_ALLOW_LAN": "true",
    "ORAL_COACH_DATA_DIR": "/var/lib/acquire-oral-coach",
}
lines = []
seen = set()
text = p.read_text(encoding="utf-8") if p.exists() else ""
for ln in text.splitlines():
    if "=" in ln and not ln.strip().startswith("#"):
        k = ln.split("=", 1)[0].strip()
        if k in wanted:
            lines.append(f"{k}={wanted[k]}")
            seen.add(k)
            continue
    lines.append(ln)
for k, v in wanted.items():
    if k not in seen:
        lines.append(f"{k}={v}")
p.write_text("\n".join(lines).rstrip() + "\n", encoding="utf-8")
print("env ok", p)
PY

# Prefer shared API venv: fresh py3.14 pip often hangs on this host.
API_VENV=/opt/acquireenglish/services/api/.venv
if [[ -x "$API_VENV/bin/uvicorn" ]] && "$API_VENV/bin/python" -c 'import uvicorn, fastapi' 2>/dev/null; then
  UVICORN_BIN="$API_VENV/bin/uvicorn"
  echo "using shared API venv: $UVICORN_BIN"
else
  if [[ ! -d .venv ]]; then
    python3 -m venv .venv
  fi
  if ! .venv/bin/python -c 'import uvicorn, fastapi' 2>/dev/null; then
    .venv/bin/pip install -q -r requirements.txt
  fi
  UVICORN_BIN="${PATH_REMOTE}/.venv/bin/uvicorn"
fi

cat > /etc/systemd/system/acquireenglish-oral-coach.service <<UNIT
[Unit]
Description=AcquireEnglish Oral Coach
After=network.target

[Service]
Type=simple
WorkingDirectory=${PATH_REMOTE}
EnvironmentFile=${PATH_REMOTE}/.env
Environment=PYTHONPATH=${PATH_REMOTE}
ExecStart=${UVICORN_BIN} app.main:app --host 127.0.0.1 --port ${PORT_LOCAL} --workers 1
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable acquireenglish-oral-coach >/dev/null
systemctl restart acquireenglish-oral-coach
sleep 1
systemctl is-active acquireenglish-oral-coach

mkdir -p /etc/nginx/snippets
cat > /etc/nginx/snippets/acquireenglish-oral-coach.conf <<NGX
location = /coach {
    return 301 /coach/;
}
location /coach/ {
    proxy_pass http://127.0.0.1:${PORT_LOCAL}/;
    proxy_http_version 1.1;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_read_timeout 300s;
    client_max_body_size 32m;
}
NGX

python3 - <<'PY'
from pathlib import Path
import re

needle = "include snippets/acquireenglish-oral-coach.conf;"
candidates = list(Path("/etc/nginx/sites-enabled").glob("*")) + list(
    Path("/etc/nginx/conf.d").glob("*.conf")
)
for conf in candidates:
    if not conf.is_file():
        continue
    text = conf.read_text(encoding="utf-8", errors="ignore")
    if needle in text:
        print("already included", conf)
        continue
    if "acquireenglish" not in text and "curlhairai" not in text:
        continue
    m = re.search(r"server_name[^\n]*(?:acquireenglish|curlhairai)[^\n]*;", text)
    if not m:
        m = re.search(r"listen\s+443[^;]*;", text)
    if not m:
        continue
    idx = text.rfind("server {", 0, m.start())
    if idx < 0:
        continue
    brace = text.find("{", idx)
    if brace < 0:
        continue
    text = text[: brace + 1] + f"\n    {needle}" + text[brace + 1 :]
    conf.write_text(text, encoding="utf-8")
    print("patched", conf)
PY

nginx -t
systemctl reload nginx
curl -fsS "http://127.0.0.1:${PORT_LOCAL}/api/health"
echo
REMOTE

echo "==> Public health"
curl -fsS "$PUBLIC_BASE/coach/api/health" && echo
echo "Oral coach public URL: $PUBLIC_BASE/coach"
