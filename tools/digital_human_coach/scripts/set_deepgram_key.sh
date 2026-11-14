#!/usr/bin/env bash
# Write DEEPGRAM_API_KEY into agent .env + ECS oral_coach.
# Create a key at: https://console.deepgram.com → API Keys
# Usage:
#   ./scripts/set_deepgram_key.sh YOUR_DEEPGRAM_KEY
#   APPLY_ORAL_COACH=1 ./scripts/set_deepgram_key.sh YOUR_DEEPGRAM_KEY
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KEY="${1:-}"
if [[ -z "$KEY" ]]; then
  echo "Usage: $0 YOUR_DEEPGRAM_API_KEY"
  echo "Get one: https://console.deepgram.com → API Keys → Create Key"
  exit 1
fi

ENV_FILE="$ROOT/.env"
if [[ ! -f "$ENV_FILE" ]]; then
  cp "$ROOT/.env.example" "$ENV_FILE"
fi

python3 - <<PY
from pathlib import Path
p = Path("$ENV_FILE")
wanted = {
    "DEEPGRAM_API_KEY": "$KEY",
    "STT_PROVIDER": "deepgram",
    "TTS_PROVIDER": "auto",
}
lines, seen = [], set()
text = p.read_text(encoding="utf-8") if p.exists() else ""
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
print("updated", p)
PY

if [[ "${APPLY_ORAL_COACH:-0}" == "1" ]]; then
  HOST="${DEPLOY_HOST:-root@8.163.45.100}"
  ssh "$HOST" "python3 - <<'PY'
from pathlib import Path
p = Path('/opt/acquireenglish/tools/oral_coach/.env')
wanted = {
    'ASR_PROVIDER': 'deepgram',
    'DEEPGRAM_API_KEY': '''$KEY''',
}
lines, seen = [], set()
text = p.read_text(encoding='utf-8') if p.exists() else ''
for ln in text.splitlines():
    if '=' in ln and not ln.strip().startswith('#'):
        k = ln.split('=', 1)[0].strip()
        if k in wanted:
            lines.append(f'{k}={wanted[k]}')
            seen.add(k)
            continue
    lines.append(ln)
for k, v in wanted.items():
    if k not in seen:
        lines.append(f'{k}={v}')
p.write_text('\\n'.join(lines).rstrip() + '\\n', encoding='utf-8')
print('updated', p)
PY
systemctl restart acquireenglish-oral-coach
sleep 1
curl -fsS http://127.0.0.1:8770/api/health
echo"
  echo "ECS oral_coach ASR → deepgram"
fi

echo "Done. Agent will use Deepgram STT (+ Aura TTS when TTS_PROVIDER=auto)."
