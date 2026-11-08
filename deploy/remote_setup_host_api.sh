#!/usr/bin/env bash
set -euo pipefail

API=/opt/acquireenglish/services/api
cd "$API"
python3 -m venv .venv
# shellcheck disable=SC1091
source .venv/bin/activate
pip install -U pip -i https://pypi.tuna.tsinghua.edu.cn/simple
# Prefer binary wheels; allow slightly newer deps for Python 3.14
pip install -i https://pypi.tuna.tsinghua.edu.cn/simple \
  "fastapi>=0.115.6,<0.129" \
  "uvicorn[standard]>=0.32.1,<0.40" \
  "pydantic>=2.10.3,<2.13" \
  "pydantic-settings>=2.6.1,<2.13" \
  "email-validator>=2.2.0" \
  "python-jose[cryptography]>=3.3.0" \
  "passlib[bcrypt]>=1.7.4" \
  "bcrypt>=4.0.1,<4.1" \
  "sqlalchemy>=2.0.36,<2.1" \
  "aiosqlite>=0.20.0" \
  "python-multipart>=0.0.17" \
  "httpx>=0.28.1"

ENV_FILE="$API/.env"
if [[ ! -f "$ENV_FILE" ]]; then
  SECRET=$(openssl rand -base64 48 | tr -d '\n/+=' | head -c 64)
  cat > "$ENV_FILE" <<EOF
SECRET_KEY=${SECRET}
ACCESS_TOKEN_EXPIRE_MINUTES=10080
DATABASE_URL=sqlite+aiosqlite:///./acquire_english.db
CORS_ORIGINS=https://acquireenglish.curlhairai.com,http://localhost:5173
MEDIA_PUBLIC_BASE=https://acquireenglish.curlhairai.com
EOF
  chmod 600 "$ENV_FILE"
fi

# Host path DB (not docker /data)
if grep -q '^DATABASE_URL=' "$ENV_FILE"; then
  sed -i 's|^DATABASE_URL=.*|DATABASE_URL=sqlite+aiosqlite:///./acquire_english.db|' "$ENV_FILE"
fi
if grep -q '^MEDIA_PUBLIC_BASE=' "$ENV_FILE"; then
  sed -i 's|^MEDIA_PUBLIC_BASE=.*|MEDIA_PUBLIC_BASE=https://acquireenglish.curlhairai.com|' "$ENV_FILE"
else
  echo 'MEDIA_PUBLIC_BASE=https://acquireenglish.curlhairai.com' >> "$ENV_FILE"
fi

python -c "from app.main import app; print('app_ok', app.title)"

cp /opt/acquireenglish/deploy/acquireenglish-api.service /etc/systemd/system/acquireenglish-api.service
systemctl daemon-reload
systemctl enable --now acquireenglish-api.service
sleep 1
systemctl --no-pager --full status acquireenglish-api.service | head -n 25
curl -sf http://127.0.0.1:5200/api/health
echo
