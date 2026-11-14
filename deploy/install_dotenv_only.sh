#!/usr/bin/env bash
set -euo pipefail
pkill -f 'pip install' || true
sleep 1
VENV=/opt/acquireenglish/services/api/.venv
"$VENV/bin/pip" install -q python-dotenv
"$VENV/bin/python" -c 'import dotenv; print("dotenv_ok")'
# numpy optional for mock mode; skip compile on py3.14
systemctl is-active acquireenglish-oral-coach || systemctl restart acquireenglish-oral-coach
sleep 1
systemctl is-active acquireenglish-oral-coach
curl -fsS https://acquireenglish.curlhairai.com/coach/api/health
echo
curl -fsS https://acquireenglish.curlhairai.com/api/health
echo
