#!/usr/bin/env bash
# Write DEEPSEEK_API_KEY into local agent .env (and optionally ECS oral_coach).
# Usage:
#   ./scripts/set_deepseek_key.sh sk-xxxxxxxx
#   APPLY_ORAL_COACH=1 ./scripts/set_deepseek_key.sh sk-xxxxxxxx   # also update ECS /coach
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KEY="${1:-}"
if [[ -z "$KEY" ]]; then
  echo "Usage: $0 sk-your-deepseek-key"
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
    "LLM_PROVIDER": "deepseek",
    "DEEPSEEK_API_KEY": "$KEY",
    "DEEPSEEK_MODEL": "deepseek-chat",
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
    'LLM_PROVIDER': 'deepseek',
    'DEEPSEEK_API_KEY': '''$KEY''',
    'DEEPSEEK_MODEL': 'deepseek-chat',
    'OPENAI_BASE_URL': 'https://api.deepseek.com/v1',
    'OPENAI_MODEL': 'deepseek-chat',
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
  echo "ECS oral_coach restarted with DeepSeek"
fi

echo "Done. Start agent: ./scripts/run_agent.sh"
