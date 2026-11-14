#!/usr/bin/env bash
set -euo pipefail
python3 - <<'PY'
from pathlib import Path
text = Path("/opt/acquireenglish/services/api/.env").read_text(encoding="utf-8", errors="ignore")
for ln in text.splitlines():
    if ln.startswith("DASHSCOPE_API_KEY="):
        print(ln.split("=", 1)[1].strip())
        break
else:
    raise SystemExit("DASHSCOPE missing")
PY
# also report bili without printing full value
python3 - <<'PY'
from pathlib import Path
text = Path("/opt/acquireenglish/services/api/.env").read_text(encoding="utf-8", errors="ignore")
has=False
for ln in text.splitlines():
    if ln.startswith("BILIBILI_COOKIE="):
        v=ln.split("=",1)[1].strip()
        print("BILI", "SET" if v else "EMPTY", "len", len(v))
        has=True
        break
if not has:
    print("BILI MISSING")
PY
curl -fsS https://acquireenglish.curlhairai.com/coach/api/health; echo
