#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
VENDOR="$ROOT/vendor/zemksh-voice"
# shellcheck disable=SC1091
source "$ROOT/.venv/bin/activate"
export VOICE_ALLOW_LAN="${VOICE_ALLOW_LAN:-true}"
# Load .env into the process for uvicorn child.
set -a
# shellcheck disable=SC1091
source "$VENDOR/.env"
set +a
HOST="${VOICE_HOST:-0.0.0.0}"
PORT="${VOICE_PORT:-8765}"
cd "$VENDOR"
exec uvicorn backend.app.main:app --host "$HOST" --port "$PORT" --workers 1
