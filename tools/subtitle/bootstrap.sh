#!/usr/bin/env bash
# Bootstrap the vendored auto-subs + whisper-subtitle-generator stack.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

if [[ ! -d .venv ]]; then
  python3 -m venv .venv
fi
# shellcheck disable=SC1091
source .venv/bin/activate

python -m pip install --upgrade pip
python -m pip install -r requirements.txt
python -m pip install -e "./vendor/auto-subs[transcribe]"
python -m pip install -e "./vendor/whisper-subtitle-generator"

echo "Ready. Try:"
echo "  $ROOT/.venv/bin/python $ROOT/fill_missing.py --help"
