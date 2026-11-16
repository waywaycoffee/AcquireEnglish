#!/usr/bin/env bash
# Write SMS / WeChat auth env on the API host. Do not commit filled secrets.
set -euo pipefail

ENV_FILE="${ENV_FILE:-/opt/acquireenglish/services/api/.env}"
SERVICE_NAME="${SERVICE_NAME:-acquireenglish-api}"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "missing $ENV_FILE" >&2
  exit 1
fi

upsert() {
  local key="$1"
  local value="$2"
  if grep -q "^${key}=" "$ENV_FILE"; then
    python3 - "$ENV_FILE" "$key" "$value" <<'PY'
import pathlib, sys
path, key, value = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3]
lines = path.read_text(encoding="utf-8").splitlines()
out = []
found = False
for line in lines:
    if line.startswith(key + "="):
        out.append(f"{key}={value}")
        found = True
    else:
        out.append(line)
if not found:
    out.append(f"{key}={value}")
path.write_text("\n".join(out) + "\n", encoding="utf-8")
PY
  else
    printf '%s=%s\n' "$key" "$value" >>"$ENV_FILE"
  fi
}

echo "Editing $ENV_FILE"
read -r -p "ALIYUN_SMS_ACCESS_KEY_ID: " AK
read -r -p "ALIYUN_SMS_ACCESS_KEY_SECRET: " SK
read -r -p "ALIYUN_SMS_SIGN_NAME: " SIGN
read -r -p "ALIYUN_SMS_TEMPLATE_CODE: " TPL
read -r -p "WECHAT_APP_ID (可空): " WX_ID
read -r -p "WECHAT_APP_SECRET (可空): " WX_SECRET

upsert AUTH_SMS_MOCK false
upsert ALIYUN_SMS_ACCESS_KEY_ID "$AK"
upsert ALIYUN_SMS_ACCESS_KEY_SECRET "$SK"
upsert ALIYUN_SMS_SIGN_NAME "$SIGN"
upsert ALIYUN_SMS_TEMPLATE_CODE "$TPL"
upsert ALIYUN_SMS_REGION cn-hangzhou

if [[ -n "${WX_ID}" && -n "${WX_SECRET}" ]]; then
  upsert AUTH_WECHAT_MOCK false
  upsert WECHAT_APP_ID "$WX_ID"
  upsert WECHAT_APP_SECRET "$WX_SECRET"
else
  echo "WeChat secrets skipped — keep AUTH_WECHAT_MOCK as-is"
fi

if systemctl list-unit-files | grep -q "^${SERVICE_NAME}"; then
  systemctl restart "$SERVICE_NAME"
  systemctl --no-pager --full status "$SERVICE_NAME" | head -20
else
  echo "service $SERVICE_NAME not found; restart API manually"
fi

curl -fsS https://acquireenglish.curlhairai.com/api/health || true
echo
echo "Done. Confirm auth_sms_provider=aliyun and auth_wechat_mock=false when WeChat filled."
