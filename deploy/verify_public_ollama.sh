#!/usr/bin/env bash
set -euo pipefail
echo "=== loopback via :8443 ==="
curl -sS --max-time 10 -H 'Host: acquireenglish.curlhairai.com' \
  http://127.0.0.1:8443/ollama/v1/models
echo
echo "=== chat completion ==="
curl -sS --max-time 60 -H 'Host: acquireenglish.curlhairai.com' \
  http://127.0.0.1:8443/ollama/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{"model":"qwen2.5:3b","messages":[{"role":"user","content":"Translate to Chinese only: Hello"}],"max_tokens":32}'
echo
