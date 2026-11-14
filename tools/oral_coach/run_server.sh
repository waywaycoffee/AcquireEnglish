#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$ROOT/.venv/bin/activate"
set -a
# shellcheck disable=SC1091
source "$ROOT/.env"
set +a
HOST="${ORAL_COACH_HOST:-0.0.0.0}"
PORT="${ORAL_COACH_PORT:-8770}"
cd "$ROOT"
exec uvicorn app.main:app --host "$HOST" --port "$PORT" --workers 1
