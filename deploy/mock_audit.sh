#!/usr/bin/env bash
set -euo pipefail
echo "== API health =="
curl -fsS https://acquireenglish.curlhairai.com/api/health; echo
echo "== Coach health =="
curl -fsS https://acquireenglish.curlhairai.com/coach/api/health; echo
echo "== Coach providers =="
curl -fsS https://acquireenglish.curlhairai.com/coach/api/providers; echo
echo "== LiveKit =="
curl -fsS https://acquireenglish.curlhairai.com/api/livekit/status; echo
python3 - <<'PY'
from pathlib import Path

def dump(path, keys):
    text = Path(path).read_text(encoding="utf-8", errors="ignore") if Path(path).exists() else ""
    print("##", path)
    for k in keys:
        for ln in text.splitlines():
            if ln.startswith(k + "="):
                v = ln.split("=", 1)[1].strip()
                secret = k.endswith("KEY") or k.endswith("SECRET") or "COOKIE" in k
                print(f"{k}={'SET' if v else 'EMPTY'}" if secret else f"{k}={v or 'EMPTY'}")
                break
        else:
            print(f"{k}=MISSING")

dump(
    "/opt/acquireenglish/services/api/.env",
    [
        "AUTH_SMS_MOCK",
        "AUTH_WECHAT_MOCK",
        "AUTH_SMS_WEBHOOK_URL",
        "WECHAT_APP_ID",
        "DASHSCOPE_API_KEY",
        "BILIBILI_COOKIE",
        "LIVEKIT_URL",
    ],
)
dump(
    "/opt/acquireenglish/tools/oral_coach/.env",
    [
        "ASR_PROVIDER",
        "PRON_PROVIDER",
        "LLM_PROVIDER",
        "TTS_PROVIDER",
        "AVATAR_PROVIDER",
        "DEEPGRAM_API_KEY",
        "DEEPSEEK_API_KEY",
    ],
)
PY
