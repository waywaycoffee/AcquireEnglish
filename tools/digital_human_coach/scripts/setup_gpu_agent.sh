#!/usr/bin/env bash
# Bootstrap LiveKit Agent on a GPU workstation (e.g. RTX 5060 Ti 16G).
# Usage:
#   cd tools/digital_human_coach
#   ./scripts/setup_gpu_agent.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PY="${PYTHON:-}"
if [[ -z "$PY" ]]; then
  for cand in python3.12 python3.11 python3; do
    if command -v "$cand" >/dev/null 2>&1; then
      PY="$cand"
      break
    fi
  done
fi
if [[ -z "$PY" ]]; then
  echo "Need Python 3.11+"; exit 1
fi

echo "==> Python: $($PY --version)"
if [[ ! -d .venv ]]; then
  "$PY" -m venv .venv
fi
# shellcheck disable=SC1091
source .venv/bin/activate
python -m pip install -U pip wheel
python -m pip install -r requirements-agent.txt

if [[ ! -f .env ]]; then
  cp .env.example .env
  echo "==> Created .env from .env.example — fill LIVEKIT_* and OPENAI_API_KEY"
else
  echo "==> .env already exists"
fi

echo "==> Download Silero / plugin assets (safe to re-run)"
python -m agent.main download-files || true

cat <<'MSG'

Setup done.

1) Edit tools/digital_human_coach/.env
   - LIVEKIT_URL / LIVEKIT_API_KEY / LIVEKIT_API_SECRET
   - OPENAI_API_KEY (agent LLM+TTS)
   - ORAL_COACH_URL already points at production /coach

2) On the API server also set the SAME LiveKit trio in
   /opt/acquireenglish/services/api/.env then:
   systemctl restart acquireenglish-api

3) Start worker:
   cd tools/digital_human_coach
   source .venv/bin/activate
   ./scripts/run_agent.sh

4) App → Settings → LiveKit 房间地址 = same wss://…
MSG
