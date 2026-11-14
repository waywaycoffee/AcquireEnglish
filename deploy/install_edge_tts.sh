#!/usr/bin/env bash
set -euo pipefail

API_VENV=/opt/acquireenglish/services/api/.venv
COACH_VENV=/opt/acquireenglish/tools/oral_coach/.venv
COACH_ENV=/opt/acquireenglish/tools/oral_coach/.env

install_edge() {
  local py="$1"
  echo "==> trying $py"
  "$py" -m pip install -U pip setuptools wheel -q || true
  # Prefer binary wheels; use PyPI + short retries
  if timeout 90 "$py" -m pip install --only-binary=:all: -q edge-tts; then
    echo "installed_via_only_binary"
    return 0
  fi
  if timeout 120 "$py" -m pip install -i https://pypi.tuna.tsinghua.edu.cn/simple -q edge-tts; then
    echo "installed_via_tuna"
    return 0
  fi
  if timeout 120 "$py" -m pip install -q edge-tts; then
    echo "installed_via_pypi"
    return 0
  fi
  return 1
}

ok=0
if [[ -x "$API_VENV/bin/python" ]]; then
  if "$API_VENV/bin/python" -c 'import edge_tts' 2>/dev/null; then
    echo "api_venv_already_has_edge_tts"
    ok=1
  elif install_edge "$API_VENV/bin/python"; then
    ok=1
  fi
fi

# Fallback: dedicated coach venv on a working interpreter if available
if [[ "$ok" -ne 1 ]]; then
  for cand in python3.12 python3.11 python3.13 python3; do
    if command -v "$cand" >/dev/null 2>&1; then
      ver=$("$cand" -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
      echo "candidate $cand ($ver)"
      # Avoid py3.14 source builds if possible by preferring 3.12/3.11
      if [[ "$ver" == "3.14" ]]; then
        continue
      fi
      if [[ ! -x "$COACH_VENV/bin/python" ]]; then
        "$cand" -m venv "$COACH_VENV"
      fi
      if install_edge "$COACH_VENV/bin/python"; then
        # also ensure fastapi/uvicorn present for coach
        timeout 180 "$COACH_VENV/bin/python" -m pip install -q -r /opt/acquireenglish/tools/oral_coach/requirements.txt || true
        ok=1
        # Retarget systemd unit to coach venv uvicorn
        if [[ -x "$COACH_VENV/bin/uvicorn" ]]; then
          cat > /etc/systemd/system/acquireenglish-oral-coach.service <<UNIT
[Unit]
Description=AcquireEnglish Oral Coach
After=network.target

[Service]
Type=simple
WorkingDirectory=/opt/acquireenglish/tools/oral_coach
EnvironmentFile=/opt/acquireenglish/tools/oral_coach/.env
Environment=PYTHONPATH=/opt/acquireenglish/tools/oral_coach
ExecStart=${COACH_VENV}/bin/uvicorn app.main:app --host 127.0.0.1 --port 8770 --workers 1
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
UNIT
          systemctl daemon-reload
        fi
        break
      fi
    fi
  done
fi

# Last resort: try api venv anyway even on 3.14 without only-binary
if [[ "$ok" -ne 1 && -x "$API_VENV/bin/python" ]]; then
  echo "==> last resort api venv plain install"
  if timeout 180 "$API_VENV/bin/pip" install -q edge-tts aiohttp; then
    ok=1
  fi
fi

if [[ "$ok" -ne 1 ]]; then
  echo "EDGE_TTS_INSTALL_FAILED"
  exit 1
fi

# Point TTS to edge
python3 - <<'PY'
from pathlib import Path
p = Path("/opt/acquireenglish/tools/oral_coach/.env")
text = p.read_text(encoding="utf-8") if p.exists() else ""
lines = []
seen = set()
wanted = {
    "TTS_PROVIDER": "edge",
    "EDGE_TTS_VOICE": "en-US-JennyNeural",
}
for ln in text.splitlines():
    if "=" in ln and not ln.strip().startswith("#"):
        k = ln.split("=", 1)[0].strip()
        if k in wanted:
            lines.append(f"{k}={wanted[k]}")
            seen.add(k)
            continue
    lines.append(ln)
for k, v in wanted.items():
    if k not in seen:
        lines.append(f"{k}={v}")
p.write_text("\n".join(lines).rstrip() + "\n", encoding="utf-8")
print("env_tts_edge")
PY

# Verify import with the interpreter that will run coach
UNIT_PY=$(systemctl show acquireenglish-oral-coach -p ExecStart --value | awk '{print $1}')
if [[ -x "$API_VENV/bin/python" ]] && "$API_VENV/bin/python" -c 'import edge_tts' 2>/dev/null; then
  "$API_VENV/bin/python" -c 'import edge_tts; print("import_ok", getattr(edge_tts, "__version__", "?"))'
elif [[ -x "$COACH_VENV/bin/python" ]]; then
  "$COACH_VENV/bin/python" -c 'import edge_tts; print("import_ok_coach_venv", getattr(edge_tts, "__version__", "?"))'
fi

systemctl restart acquireenglish-oral-coach
sleep 1
systemctl is-active acquireenglish-oral-coach
curl -fsS https://acquireenglish.curlhairai.com/coach/api/health
echo
