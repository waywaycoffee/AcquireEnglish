#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
VENDOR="$ROOT/vendor/zemksh-voice"
cd "$ROOT"

if [[ ! -d "$VENDOR/backend" ]]; then
  echo "Missing vendor at $VENDOR" >&2
  exit 1
fi

python3 "$ROOT/patches/0001-shadow-and-lan.patch.py"

python3 -m venv "$ROOT/.venv"
# shellcheck disable=SC1091
source "$ROOT/.venv/bin/activate"
pip install -U pip
pip install -r "$VENDOR/backend/requirements.txt"

if [[ ! -f "$VENDOR/.env" ]]; then
  cp "$VENDOR/.env.example" "$VENDOR/.env"
  # Sensible defaults for AcquireEnglish laptop sidecar + phone LAN.
  {
    echo "VOICE_ALLOW_LAN=true"
    echo "MOCK_MODE=false"
  } >> "$VENDOR/.env"
  echo "Wrote $VENDOR/.env — set GEMMA_MODEL if you want topic rubric scores."
fi

echo "Optional Whisper model (needed for real transcription):"
echo "  source .venv/bin/activate && python vendor/zemksh-voice/scripts/prepare_model.py"
echo "Start: ./run_server.sh"
