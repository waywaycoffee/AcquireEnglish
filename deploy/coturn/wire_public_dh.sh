#!/usr/bin/env bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a
export UCF_FORCE_CONFOLD=1
PASS="${TURN_PASSWORD:?TURN_PASSWORD required}"

# nginx public LiveTalking (CurlHair-style)
if [ -f /tmp/acquireenglish-livetalking.conf ]; then
  cp /tmp/acquireenglish-livetalking.conf /etc/nginx/snippets/acquireenglish-livetalking.conf
fi
nginx -t
systemctl reload nginx

# oral coach app + env
if [ -d /tmp/oral_coach_app ]; then
  mkdir -p /opt/acquireenglish/tools/oral_coach/app/providers
  cp -a /tmp/oral_coach_app/. /opt/acquireenglish/tools/oral_coach/app/
fi

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
set_kv LIVETALKING_URL 'http://100.115.252.55:8010'
set_kv LIVETALKING_PUBLIC_URL 'https://acquireenglish.curlhairai.com/livetalking'
set_kv TURN_URLS 'turn:acquireenglish.curlhairai.com:3478?transport=udp,turn:acquireenglish.curlhairai.com:3478?transport=tcp'
set_kv TURN_USERNAME 'acquire'
set_kv TURN_PASSWORD "$PASS"

systemctl restart acquireenglish-oral-coach
sleep 1
echo '--- health ---'
curl -sS --max-time 5 http://127.0.0.1:8770/api/health
echo
echo '--- public livetalking ---'
curl -sS -o /dev/null -w 'index:%{http_code}\n' --max-time 8 \
  https://acquireenglish.curlhairai.com/livetalking/index.html
curl -sS -o /dev/null -w 'offer_post_empty:%{http_code}\n' --max-time 8 \
  -X POST https://acquireenglish.curlhairai.com/livetalking/offer \
  -H 'Content-Type: application/json' -d '{}'
echo '--- turn conf ---'
grep -E 'realm|external-ip|user=' /etc/turnserver.conf | sed 's/user=.*/user=***/'
systemctl is-active coturn
echo wire_done
