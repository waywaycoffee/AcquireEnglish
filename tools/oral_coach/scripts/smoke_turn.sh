#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-http://127.0.0.1:8770}"
SID=$(curl -sS -X POST "$BASE/api/sessions" \
  -H 'Content-Type: application/json' \
  -d '{"course_title":"Demo","episode_title":"Ep1","current_english":"The city was too chaotic for them.","current_chinese":"这座城市对他们来说太混乱了。","difficulty":"B1"}' \
  | python3 -c 'import sys,json; print(json.load(sys.stdin)["id"])')
echo "session=$SID"
# 0.4s silent wav
python3 - <<'PY'
import wave, pathlib
p = pathlib.Path('/tmp/oral_coach_smoke.wav')
with wave.open(str(p), 'wb') as w:
    w.setnchannels(1); w.setsampwidth(2); w.setframerate(16000)
    w.writeframes(b'\x00\x00' * 6400)
print(p)
PY
curl -sS -X POST "$BASE/api/sessions/$SID/turn" \
  -F "file=@/tmp/oral_coach_smoke.wav;type=audio/wav" \
  -F "reference_text=The city was too chaotic for them." \
  | python3 -m json.tool
