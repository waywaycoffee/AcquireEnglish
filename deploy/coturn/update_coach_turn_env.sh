#!/usr/bin/env bash
set -euo pipefail
PASS="${TURN_PASSWORD:?}"
ENV=/opt/acquireenglish/tools/oral_coach/.env
touch "$ENV"
set_kv() {
  local k="$1" v="$2"
  if grep -q "^${k}=" "$ENV"; then
    sed -i "s|^${k}=.*|${k}=${v}|" "$ENV"
  else
    printf '%s=%s\n' "$k" "$v" >>"$ENV"
  fi
}
set_kv TURN_URLS 'turns:turn.curlhairai.com:443?transport=tcp'
set_kv TURN_USERNAME 'acquire'
set_kv TURN_PASSWORD "$PASS"
set_kv LIVETALKING_PUBLIC_URL 'https://acquireenglish.curlhairai.com/livetalking'
set_kv LIVETALKING_URL 'http://100.115.252.55:8010'
grep '^TURN_\|^LIVETALKING_' "$ENV" | sed 's/PASSWORD=.*/PASSWORD=***/'
systemctl restart acquireenglish-oral-coach
sleep 1
curl -sS http://127.0.0.1:8770/api/health
echo
