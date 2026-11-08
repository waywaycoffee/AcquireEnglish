#!/usr/bin/env bash
set -euo pipefail

ENV_FILE=/opt/acquireenglish/services/api/.env
mkdir -p /opt/acquireenglish/data

if [[ ! -f "$ENV_FILE" ]]; then
  SECRET=$(openssl rand -base64 48 | tr -d '\n/+=' | head -c 64)
  cat > "$ENV_FILE" <<EOF
SECRET_KEY=${SECRET}
ACCESS_TOKEN_EXPIRE_MINUTES=10080
DATABASE_URL=sqlite+aiosqlite:////data/acquire_english.db
CORS_ORIGINS=https://acquireenglish.curlhairai.com,http://localhost:5173
MEDIA_PUBLIC_BASE=https://acquireenglish.curlhairai.com
EOF
  chmod 600 "$ENV_FILE"
fi

# Normalize key settings without breaking SECRET_KEY
if grep -q '^DATABASE_URL=' "$ENV_FILE"; then
  sed -i 's|^DATABASE_URL=.*|DATABASE_URL=sqlite+aiosqlite:////data/acquire_english.db|' "$ENV_FILE"
else
  echo 'DATABASE_URL=sqlite+aiosqlite:////data/acquire_english.db' >> "$ENV_FILE"
fi

if grep -q '^MEDIA_PUBLIC_BASE=' "$ENV_FILE"; then
  sed -i 's|^MEDIA_PUBLIC_BASE=.*|MEDIA_PUBLIC_BASE=https://acquireenglish.curlhairai.com|' "$ENV_FILE"
else
  echo 'MEDIA_PUBLIC_BASE=https://acquireenglish.curlhairai.com' >> "$ENV_FILE"
fi

if grep -q '^CORS_ORIGINS=' "$ENV_FILE"; then
  sed -i 's|^CORS_ORIGINS=.*|CORS_ORIGINS=https://acquireenglish.curlhairai.com,http://localhost:5173|' "$ENV_FILE"
else
  echo 'CORS_ORIGINS=https://acquireenglish.curlhairai.com,http://localhost:5173' >> "$ENV_FILE"
fi

cd /opt/acquireenglish
docker compose -f deploy/docker-compose.yml build
docker compose -f deploy/docker-compose.yml up -d
sleep 2
docker compose -f deploy/docker-compose.yml ps
curl -sf http://127.0.0.1:5200/api/health
echo
curl -sf http://127.0.0.1:5200/api/courses | head -c 200
echo
