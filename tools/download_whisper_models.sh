#!/usr/bin/env bash
# Optional developer cache of Whisper GGML weights for desktop / GPU workers.
# Mobile App no longer downloads or ships these — do not add to pubspec.yaml.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="$ROOT/apps/mobile/assets/whisper"
FILE="$OUT_DIR/ggml-base.en.bin"
EXPECTED_SHA="a03779c86df3323075f5e796cb2ce5029f00ec8869eee3fdfb897afe36c6d002"
REV="5359861c739e955e79d9a303bcbc70fb988958b1"
PATH_SUFFIX="ggerganov/whisper.cpp/resolve/${REV}/ggml-base.en.bin"

mkdir -p "$OUT_DIR"
if [[ -f "$FILE" ]]; then
  ACTUAL="$(shasum -a 256 "$FILE" | awk '{print $1}')"
  if [[ "$ACTUAL" == "$EXPECTED_SHA" ]]; then
    echo "Already present (dev cache only, not shipped): $FILE"
    exit 0
  fi
  echo "Checksum mismatch — re-downloading"
  rm -f "$FILE"
fi

download() {
  local url="$1"
  echo "Downloading: $url"
  curl -L --fail --retry 3 --connect-timeout 20 -o "$FILE.part" "$url"
  mv "$FILE.part" "$FILE"
}

download "https://hf-mirror.com/${PATH_SUFFIX}" \
  || download "https://huggingface.co/${PATH_SUFFIX}"

ACTUAL="$(shasum -a 256 "$FILE" | awk '{print $1}')"
if [[ "$ACTUAL" != "$EXPECTED_SHA" ]]; then
  echo "SHA-256 mismatch: expected $EXPECTED_SHA, got $ACTUAL" >&2
  rm -f "$FILE"
  exit 1
fi
ls -lh "$FILE"
echo "OK (dev cache). App still downloads on first ASR use — do not list in pubspec."
