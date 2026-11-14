#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"
python3 -m venv .venv
# shellcheck disable=SC1091
source .venv/bin/activate
pip install -U pip
pip install -r requirements.txt
if [[ ! -f .env ]]; then
  cp .env.example .env
  echo "Wrote .env (default providers=mock, avatar=livetalking)."
fi
echo "Start: ./run_server.sh"
echo "Health: curl http://127.0.0.1:8770/api/health"
