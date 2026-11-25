#!/usr/bin/env bash
# Write WeChat Pay (App) merchant credentials on the API host.
# Prefer storing apiclient_key.pem on disk; .env only holds the absolute path.
# Do not commit filled secrets.
set -euo pipefail

ENV_FILE="${ENV_FILE:-/opt/acquireenglish/services/api/.env}"
SERVICE_NAME="${SERVICE_NAME:-acquireenglish-api}"
SECRETS_DIR="${SECRETS_DIR:-/opt/acquireenglish/secrets/wechat_pay}"
NOTIFY_URL_DEFAULT="https://acquireenglish.curlhairai.com/api/assets/wechat/notify"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "missing $ENV_FILE" >&2
  exit 1
fi

mkdir -p "$SECRETS_DIR"
chmod 700 "$SECRETS_DIR"

upsert() {
  local key="$1"
  local value="$2"
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
}

echo "Editing $ENV_FILE"
echo "从 pay.weixin.qq.com 商户平台 → 账户中心 → API安全 获取下列值。"
echo "AppID 须已与商户号绑定（开放平台移动应用 wx00b4272a8eabb1cd）。"
echo

read -r -p "WECHAT_MCH_ID (商户号): " MCH_ID
read -r -p "WECHAT_MCH_SERIAL_NO (API证书序列号): " SERIAL
read -r -p "WECHAT_MCH_API_V3_KEY (32位): " API_V3
read -r -p "WECHAT_PAY_NOTIFY_URL [${NOTIFY_URL_DEFAULT}]: " NOTIFY
NOTIFY="${NOTIFY:-$NOTIFY_URL_DEFAULT}"

if [[ -z "${MCH_ID}" || -z "${SERIAL}" || -z "${API_V3}" ]]; then
  echo "MCH_ID / SERIAL_NO / API_V3_KEY 均为必填" >&2
  exit 1
fi
if [[ "${#API_V3}" -ne 32 ]]; then
  echo "WECHAT_MCH_API_V3_KEY 长度必须为 32（当前 ${#API_V3}）" >&2
  exit 1
fi

KEY_PATH="${SECRETS_DIR}/apiclient_key.pem"
echo
echo "商户私钥 apiclient_key.pem："
echo "  1) 粘贴 PEM 全文（含 BEGIN/END），单独一行输入 END_PEM 结束"
echo "  2) 或先把文件放到 ${KEY_PATH} 后直接回车跳过粘贴"
read -r -p "选择 [paste/file，默认 paste]: " MODE
MODE="${MODE:-paste}"

if [[ "$MODE" == "file" || "$MODE" == "f" ]]; then
  if [[ ! -f "$KEY_PATH" ]]; then
    echo "未找到 ${KEY_PATH}。请先 scp 上传后再重跑。" >&2
    exit 1
  fi
else
  echo "粘贴 PEM（结束后单独一行输入 END_PEM）："
  PEM_BODY=""
  while IFS= read -r line; do
    if [[ "$line" == "END_PEM" ]]; then
      break
    fi
    PEM_BODY+="${line}"$'\n'
  done
  if [[ "$PEM_BODY" != *"BEGIN"* || "$PEM_BODY" != *"END"* ]]; then
    echo "PEM 内容无效" >&2
    exit 1
  fi
  printf '%s' "$PEM_BODY" >"$KEY_PATH"
fi

chmod 600 "$KEY_PATH"
python3 - "$KEY_PATH" <<'PY'
from pathlib import Path
import sys
from cryptography.hazmat.primitives import serialization
pem = Path(sys.argv[1]).read_bytes()
serialization.load_pem_private_key(pem, password=None)
print("private key OK")
PY

upsert WECHAT_MCH_ID "$MCH_ID"
upsert WECHAT_MCH_SERIAL_NO "$SERIAL"
upsert WECHAT_MCH_API_V3_KEY "$API_V3"
upsert WECHAT_MCH_PRIVATE_KEY "$KEY_PATH"
upsert WECHAT_PAY_NOTIFY_URL "$NOTIFY"

if systemctl list-unit-files | grep -q "^${SERVICE_NAME}"; then
  systemctl restart "$SERVICE_NAME"
  sleep 2
  systemctl --no-pager --full status "$SERVICE_NAME" | head -20
else
  echo "service $SERVICE_NAME not found; restart API manually"
fi

echo
curl -fsS https://acquireenglish.curlhairai.com/api/health | python3 -m json.tool
echo
curl -fsS https://acquireenglish.curlhairai.com/api/commerce/pay-status | python3 -m json.tool
echo
echo "Done. Expect wechat_pay_configured=true and wechat_configured=true."
