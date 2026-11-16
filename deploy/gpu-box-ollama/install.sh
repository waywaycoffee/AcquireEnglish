#!/usr/bin/env bash
# Install / configure Ollama on the 5060 Ti GPU box (same host as LiveTalking).
# DO NOT run on the Mac / laptop — run on the GPU box only.
#
# Usage (on GPU box):
#   cd /opt/acquireenglish/deploy/gpu-box-ollama
#   ./install.sh
# Optional:
#   OLLAMA_MODEL=qwen2.5:7b OLLAMA_HOST=0.0.0.0:11434 ./install.sh
set -euo pipefail

MODEL="${OLLAMA_MODEL:-qwen2.5:3b}"
HOST_BIND="${OLLAMA_HOST:-0.0.0.0:11434}"
KEEP_ALIVE="${OLLAMA_KEEP_ALIVE:-10m}"
UNIT_DIR="${OLLAMA_SYSTEMD_DIR:-/etc/systemd/system}"
DROPIN_DIR="${UNIT_DIR}/ollama.service.d"

echo "==> Target model: ${MODEL}"
echo "==> Listen: ${HOST_BIND}  keep_alive=${KEEP_ALIVE}"

if ! command -v ollama >/dev/null 2>&1; then
  echo "==> Installing Ollama…"
  curl -fsSL https://ollama.com/install.sh | sh
else
  echo "==> Ollama already installed: $(ollama --version 2>/dev/null || true)"
fi

if command -v nvidia-smi >/dev/null 2>&1; then
  echo "==> GPU:"
  nvidia-smi --query-gpu=name,memory.total,memory.free --format=csv,noheader || true
else
  echo "!! nvidia-smi not found — Ollama may fall back to CPU"
fi

echo "==> Systemd drop-in for Tailscale bind + keep-alive"
sudo mkdir -p "${DROPIN_DIR}"
sudo tee "${DROPIN_DIR}/override.conf" >/dev/null <<EOF
[Service]
Environment="OLLAMA_HOST=${HOST_BIND}"
Environment="OLLAMA_KEEP_ALIVE=${KEEP_ALIVE}"
# Prefer GPU; leave headroom for LiveTalking on the same card.
Environment="OLLAMA_NUM_PARALLEL=1"
EOF

sudo systemctl daemon-reload
sudo systemctl enable ollama
sudo systemctl restart ollama
sleep 2
sudo systemctl --no-pager --full status ollama | head -n 20 || true

echo "==> Pull model ${MODEL} (may take several minutes)…"
ollama pull "${MODEL}"

echo "==> Installed models:"
ollama list

echo ""
echo "==> Done. Verify with: ./verify.sh"
echo "    App preset Base URL: http://100.115.252.55:11434/v1"
echo "    Model: ${MODEL}"
echo ""
echo "    If Tailscale IP differs, update App → 自定义接口地址,"
echo "    or set MagicDNS: http://5060ti.tailc30b42.ts.net:11434/v1"
