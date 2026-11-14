#!/usr/bin/env bash
# Start LiveKit oral-coach agent worker.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
# shellcheck disable=SC1091
source .venv/bin/activate
set -a
# shellcheck disable=SC1091
source .env
set +a

: "${LIVEKIT_URL:?Set LIVEKIT_URL in .env}"
: "${LIVEKIT_API_KEY:?Set LIVEKIT_API_KEY in .env}"
: "${LIVEKIT_API_SECRET:?Set LIVEKIT_API_SECRET in .env}"

echo "Agent → $LIVEKIT_URL  name=${LIVEKIT_AGENT_NAME:-acquire-oral-coach}"
echo "oral_coach → ${ORAL_COACH_URL:-unset}"
exec python -m agent.main start
