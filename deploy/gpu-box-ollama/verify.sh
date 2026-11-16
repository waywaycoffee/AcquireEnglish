#!/usr/bin/env bash
# Health-check Ollama (+ optional LiveTalking) on the GPU box.
# Run on 5060 Ti or any machine on the same Tailscale.
#
# Usage:
#   ./verify.sh
#   OLLAMA_BASE=http://100.115.252.55:11434 MODEL=qwen2.5:7b ./verify.sh
set -euo pipefail

OLLAMA_BASE="${OLLAMA_BASE:-http://127.0.0.1:11434}"
# App uses OpenAI-compatible /v1; tags endpoint is native Ollama.
NATIVE_BASE="${OLLAMA_BASE%/v1}"
MODEL="${MODEL:-qwen2.5:3b}"
LIVE_URL="${LIVETALKING_URL:-http://127.0.0.1:8010}"

echo "==> Ollama tags @ ${NATIVE_BASE}/api/tags"
if ! curl -fsS --max-time 8 "${NATIVE_BASE}/api/tags" | head -c 400; then
  echo ""
  echo "FAIL: cannot reach Ollama at ${NATIVE_BASE}"
  exit 1
fi
echo ""

echo "==> OpenAI-compat models @ ${NATIVE_BASE}/v1/models"
curl -fsS --max-time 8 \
  -H 'Authorization: Bearer ollama' \
  "${NATIVE_BASE}/v1/models" | head -c 500
echo ""

echo "==> Chat smoke (${MODEL})…"
RESP="$(curl -fsS --max-time 120 \
  -H 'Authorization: Bearer ollama' \
  -H 'Content-Type: application/json' \
  "${NATIVE_BASE}/v1/chat/completions" \
  -d "$(cat <<JSON
{
  "model": "${MODEL}",
  "messages": [
    {"role": "system", "content": "You translate English to Simplified Chinese. Reply with Chinese only."},
    {"role": "user", "content": "Hello, how are you?"}
  ],
  "temperature": 0.2,
  "max_tokens": 64
}
JSON
)")"
echo "${RESP}" | head -c 800
echo ""

if echo "${RESP}" | grep -qiE '你好|怎样|怎么样|吗'; then
  echo "OK: translation-shaped reply"
else
  echo "WARN: reply did not look like Chinese — check model tag / GPU"
fi

echo "==> LiveTalking probe @ ${LIVE_URL}"
if curl -fsS --max-time 5 "${LIVE_URL}/" >/dev/null 2>&1 \
  || curl -fsS --max-time 5 "${LIVE_URL}/offer" -X OPTIONS >/dev/null 2>&1; then
  echo "OK: LiveTalking reachable"
else
  # Many LiveTalking builds expose /human or just accept WebRTC on root.
  CODE="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 5 "${LIVE_URL}/" || true)"
  if [[ "${CODE}" != "000" ]]; then
    echo "OK: LiveTalking HTTP ${CODE}"
  else
    echo "WARN: LiveTalking not reachable (optional for translation-only)"
  fi
fi

echo ""
echo "App settings:"
echo "  翻译来源 = 本地 Ollama"
echo "  Base URL = http://100.115.252.55:11434/v1"
echo "  Model    = ${MODEL}"
