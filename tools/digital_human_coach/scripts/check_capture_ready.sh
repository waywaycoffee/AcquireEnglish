#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
CAP="$ROOT/docs/digital-human-coach/captures"
mkdir -p "$CAP"

echo "==> adb devices"
if ! command -v adb >/dev/null; then
  echo "adb not found" >&2
  exit 1
fi
adb devices -l

echo "==> packages"
for pkg in com.youdao.dict.feature_speaker com.midoo.ai; do
  path="$(adb shell pm path "$pkg" 2>/dev/null | tr -d '\r' || true)"
  if [[ -n "$path" ]]; then
    echo "OK $pkg → $path"
  else
    echo "MISSING $pkg (install from store, then re-run)"
  fi
done

echo "==> mitmproxy"
command -v mitmproxy >/dev/null && mitmproxy --version | head -1 || echo "mitmproxy not installed (pipx install mitmproxy)"
command -v mitmweb >/dev/null && echo "mitmweb OK" || true

echo "==> capture dir $CAP"
echo "Ready checklist done. Next: start mitmweb, set phone proxy, exercise Hi Echo / Midoo."
