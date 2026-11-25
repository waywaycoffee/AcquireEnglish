#!/usr/bin/env bash
# From this Mac: upload merchant PEM + write WECHAT_MCH_* on ECS, then restart API.
# Usage:
#   export WECHAT_MCH_ID=...
#   export WECHAT_MCH_SERIAL_NO=...
#   export WECHAT_MCH_API_V3_KEY=...   # 32 chars
#   export WECHAT_MCH_PRIVATE_KEY_FILE=/path/to/apiclient_key.pem
#   bash deploy/apply_wechat_pay_from_local.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ECS_HOST="${ECS_HOST:-root@8.163.45.100}"
REMOTE_DIR="/opt/acquireenglish/secrets/wechat_pay"
REMOTE_KEY="${REMOTE_DIR}/apiclient_key.pem"
NOTIFY_URL="${WECHAT_PAY_NOTIFY_URL:-https://acquireenglish.curlhairai.com/api/assets/wechat/notify}"

: "${WECHAT_MCH_ID:?set WECHAT_MCH_ID}"
: "${WECHAT_MCH_SERIAL_NO:?set WECHAT_MCH_SERIAL_NO}"
: "${WECHAT_MCH_API_V3_KEY:?set WECHAT_MCH_API_V3_KEY}"
: "${WECHAT_MCH_PRIVATE_KEY_FILE:?set WECHAT_MCH_PRIVATE_KEY_FILE=/path/to/apiclient_key.pem}"

if [[ ! -f "$WECHAT_MCH_PRIVATE_KEY_FILE" ]]; then
  echo "missing private key file: $WECHAT_MCH_PRIVATE_KEY_FILE" >&2
  exit 1
fi
if [[ "${#WECHAT_MCH_API_V3_KEY}" -ne 32 ]]; then
  echo "WECHAT_MCH_API_V3_KEY must be 32 chars" >&2
  exit 1
fi

python3 - "$WECHAT_MCH_PRIVATE_KEY_FILE" <<'PY'
from pathlib import Path
import sys
from cryptography.hazmat.primitives import serialization
serialization.load_pem_private_key(Path(sys.argv[1]).read_bytes(), password=None)
print("local private key OK")
PY

ssh -o BatchMode=yes "$ECS_HOST" "mkdir -p '$REMOTE_DIR' && chmod 700 /opt/acquireenglish/secrets '$REMOTE_DIR'"
scp -o BatchMode=yes "$WECHAT_MCH_PRIVATE_KEY_FILE" "${ECS_HOST}:${REMOTE_KEY}"
ssh -o BatchMode=yes "$ECS_HOST" "chmod 600 '$REMOTE_KEY'"

# Push configure script if missing/outdated, then non-interactive upsert via python.
scp -o BatchMode=yes \
  "$ROOT/deploy/configure_wechat_pay_env.sh" \
  "${ECS_HOST}:/opt/acquireenglish/deploy/configure_wechat_pay_env.sh"

ssh -o BatchMode=yes "$ECS_HOST" \
  WECHAT_MCH_ID="$WECHAT_MCH_ID" \
  WECHAT_MCH_SERIAL_NO="$WECHAT_MCH_SERIAL_NO" \
  WECHAT_MCH_API_V3_KEY="$WECHAT_MCH_API_V3_KEY" \
  WECHAT_MCH_PRIVATE_KEY="$REMOTE_KEY" \
  WECHAT_PAY_NOTIFY_URL="$NOTIFY_URL" \
  bash -s <<'EOF'
set -euo pipefail
ENV_FILE=/opt/acquireenglish/services/api/.env
upsert() {
  python3 - "$ENV_FILE" "$1" "$2" <<'PY'
import pathlib, sys
path, key, value = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3]
lines = path.read_text(encoding="utf-8").splitlines()
out, found = [], False
for line in lines:
    if line.startswith(key + "="):
        out.append(f"{key}={value}"); found = True
    else:
        out.append(line)
if not found:
    out.append(f"{key}={value}")
path.write_text("\n".join(out) + "\n", encoding="utf-8")
PY
}
upsert WECHAT_MCH_ID "$WECHAT_MCH_ID"
upsert WECHAT_MCH_SERIAL_NO "$WECHAT_MCH_SERIAL_NO"
upsert WECHAT_MCH_API_V3_KEY "$WECHAT_MCH_API_V3_KEY"
upsert WECHAT_MCH_PRIVATE_KEY "$WECHAT_MCH_PRIVATE_KEY"
upsert WECHAT_PAY_NOTIFY_URL "$WECHAT_PAY_NOTIFY_URL"
systemctl restart acquireenglish-api
sleep 2
systemctl --no-pager --full status acquireenglish-api | head -15
EOF

echo
curl -fsS https://acquireenglish.curlhairai.com/api/health | python3 -m json.tool
echo
curl -fsS https://acquireenglish.curlhairai.com/api/commerce/pay-status | python3 -m json.tool
echo
echo "Expect wechat_pay_configured=true"
