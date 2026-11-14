#!/usr/bin/env bash
set -euo pipefail
echo "API=$(systemctl is-active acquireenglish-api)"
echo "COACH=$(systemctl is-active acquireenglish-oral-coach)"
echo "NGINX=$(systemctl is-active nginx)"
curl -fsS http://127.0.0.1:5200/api/health; echo
curl -fsS http://127.0.0.1:8770/api/health; echo
curl -fsS http://127.0.0.1:5200/api/livekit/status; echo
curl -fsS -o /dev/null -w "web=%{http_code}\n" https://acquireenglish.curlhairai.com/
python3 - <<'PY'
from pathlib import Path

def status(path, keys):
    text = Path(path).read_text(encoding="utf-8", errors="ignore") if Path(path).exists() else ""
    for k in keys:
        for ln in text.splitlines():
            if ln.startswith(k + "="):
                v = ln.split("=", 1)[1].strip()
                print(f"{Path(path).name}:{k}={'SET' if v else 'EMPTY'}")
                break
        else:
            print(f"{Path(path).name}:{k}=MISSING")

status(
    "/opt/acquireenglish/services/api/.env",
    ["DASHSCOPE_API_KEY", "BILIBILI_COOKIE", "LIVEKIT_URL", "LIVEKIT_API_KEY", "WECHAT_APP_ID"],
)
status(
    "/opt/acquireenglish/tools/oral_coach/.env",
    ["DEEPSEEK_API_KEY", "DEEPGRAM_API_KEY", "TTS_PROVIDER", "ASR_PROVIDER", "LLM_PROVIDER"],
)
PY
