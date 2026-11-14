#!/usr/bin/env bash
# Deploy AcquireEnglish API to Guangzhou ECS (systemd on :5200, nginx HTTPS).
#
# Usage:
#   ./deploy.sh
# Optional:
#   DEPLOY_HOST=root@8.163.45.100
#   DEPLOY_PATH=/opt/acquireenglish/services/api
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
HOST="${DEPLOY_HOST:-root@8.163.45.100}"
PATH_REMOTE="${DEPLOY_PATH:-/opt/acquireenglish/services/api}"
PUBLIC_BASE="${PUBLIC_API_BASE:-https://acquireenglish.curlhairai.com}"

echo "==> Sync app code to $HOST:$PATH_REMOTE (no --delete; keep remote-only modules)"
ssh "$HOST" "mkdir -p '$PATH_REMOTE/app/services' '$PATH_REMOTE/app/routers'"
rsync -az \
  --exclude '.venv' \
  --exclude '__pycache__' \
  --exclude '.pytest_cache' \
  --exclude '*.db' \
  --exclude '.env' \
  --exclude 'Dockerfile' \
  --exclude 'docker-compose.yml' \
  "$ROOT/app/" "$HOST:$PATH_REMOTE/app/"
rsync -az "$ROOT/requirements.txt" "$HOST:$PATH_REMOTE/requirements.txt"

echo "==> Ensure AUTH_* in remote .env"
ssh "$HOST" "python3 - <<'PY'
from pathlib import Path
p = Path('$PATH_REMOTE') / '.env'
text = p.read_text(encoding='utf-8') if p.exists() else ''
extras = {
    'AUTH_SMS_MOCK': 'true',
    'AUTH_SMS_MOCK_CODE': '123456',
    'AUTH_SMS_CODE_TTL_SECONDS': '300',
    'AUTH_WECHAT_MOCK': 'true',
    'LIVEKIT_URL': '',
    'LIVEKIT_API_KEY': '',
    'LIVEKIT_API_SECRET': '',
}
lines = text.splitlines()
keys = {ln.split('=',1)[0] for ln in lines if '=' in ln and not ln.strip().startswith('#')}
out = list(lines)
for k,v in extras.items():
    if k not in keys:
        out.append(f'{k}={v}')
p.write_text('\\n'.join(out).rstrip() + '\\n', encoding='utf-8')
print('env ok', p)
PY"

echo "==> restart systemd (skip pip unless FORCE_PIP=1; remote venv is py3.14 and pip may hang)"
if [[ "${FORCE_PIP:-0}" == "1" ]]; then
  ssh "$HOST" "cd '$PATH_REMOTE' && .venv/bin/pip install -q -r requirements.txt greenlet"
fi
ssh "$HOST" "systemctl restart acquireenglish-api && sleep 1 && systemctl is-active acquireenglish-api"

echo "==> Health"
ssh "$HOST" "curl -fsS http://127.0.0.1:5200/api/health && echo"
curl -fsS "$PUBLIC_BASE/api/health" && echo
echo "App API_BASE=$PUBLIC_BASE/"
