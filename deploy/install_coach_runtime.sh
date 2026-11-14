#!/usr/bin/env bash
set -euo pipefail
VENV=/opt/acquireenglish/services/api/.venv
"$VENV/bin/pip" install -q python-dotenv 'numpy<2.3'
"$VENV/bin/python" -c 'import dotenv,numpy; print("ok", numpy.__version__)'
systemctl restart acquireenglish-oral-coach
sleep 1
systemctl is-active acquireenglish-oral-coach
curl -fsS https://acquireenglish.curlhairai.com/coach/api/health
echo
# API still healthy
curl -fsS https://acquireenglish.curlhairai.com/api/health
echo
