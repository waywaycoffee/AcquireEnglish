#!/usr/bin/env bash
# Finish coturn + wire AcquireEnglish public digital-human path (CurlHair-style).
# Phone → HTTPS nginx → Tailscale → GPU LiveTalking; media via ECS TURN.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a
export UCF_FORCE_CONFOLD=1
PASS="${TURN_PASSWORD:?TURN_PASSWORD required}"
PUBLIC_IP="${PUBLIC_IP:-8.163.45.100}"
PRIVATE_IP="${PRIVATE_IP:-$(hostname -I | awk '{print $1}')}"

echo "wait for apt/dpkg locks..."
for i in $(seq 1 90); do
  if ! fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 \
    && ! fuser /var/lib/apt/lists/lock >/dev/null 2>&1; then
    break
  fi
  sleep 2
done

dpkg --configure -a || true
if ! dpkg -s coturn 2>/dev/null | grep -q 'Status: install ok installed'; then
  DEBIAN_FRONTEND=noninteractive apt-get install -y coturn
fi

cat >/etc/turnserver.conf <<EOF
listening-port=3478
fingerprint
lt-cred-mech
realm=acquireenglish.curlhairai.com
external-ip=${PUBLIC_IP}/${PRIVATE_IP}
user=acquire:${PASS}
min-port=49152
max-port=49200
no-cli
no-tls
no-dtls
no-multicast-peers
simple-log
EOF

if [ -f /etc/default/coturn ]; then
  sed -i 's/^#\?TURNSERVER_ENABLED=.*/TURNSERVER_ENABLED=1/' /etc/default/coturn
fi
systemctl enable coturn
systemctl restart coturn
sleep 1
systemctl is-active coturn
ss -ulnp | grep 3478 || true

# nginx snippet (CurlHair-style: public path, Tailscale upstream)
if [ -f /tmp/acquireenglish-livetalking.conf ]; then
  cp /tmp/acquireenglish-livetalking.conf /etc/nginx/snippets/acquireenglish-livetalking.conf
fi
nginx -t && systemctl reload nginx

# Oral coach: probe Tailscale internally, advertise public URL to phones
ENV=/opt/acquireenglish/tools/oral_coach/.env
touch "$ENV"
set_kv() {
  local k="$1" v="$2"
  if grep -q "^${k}=" "$ENV"; then
    sed -i "s|^${k}=.*|${k}=${v}|" "$ENV"
  else
    echo "${k}=${v}" >>"$ENV"
  fi
}
set_kv LIVETALKING_URL 'http://100.115.252.55:8010'
set_kv LIVETALKING_PUBLIC_URL 'https://acquireenglish.curlhairai.com/livetalking'
set_kv TURN_URLS 'turn:acquireenglish.curlhairai.com:3478?transport=udp,turn:acquireenglish.curlhairai.com:3478?transport=tcp'
set_kv TURN_USERNAME 'acquire'
set_kv TURN_PASSWORD "$PASS"

# Deploy updated oral_coach Python if present under /tmp
if [ -d /tmp/oral_coach_app ]; then
  cp -a /tmp/oral_coach_app/. /opt/acquireenglish/tools/oral_coach/app/
fi

systemctl restart acquireenglish-oral-coach
sleep 1
curl -sS --max-time 5 http://127.0.0.1:8770/api/health | head -c 800
echo
curl -sS -o /dev/null -w 'public_index:%{http_code}\n' --max-time 8 \
  https://acquireenglish.curlhairai.com/livetalking/index.html
echo "done"
