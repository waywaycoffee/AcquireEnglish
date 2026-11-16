#!/usr/bin/env bash
# Install + configure coturn on AcquireEnglish ECS (public TURN for LiveTalking).
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a
export UCF_FORCE_CONFOLD=1

PUBLIC_IP="${PUBLIC_IP:-$(curl -4 -sS --max-time 5 ifconfig.me || true)}"
PRIVATE_IP="${PRIVATE_IP:-$(hostname -I | awk '{print $1}')}"
REALM="${TURN_REALM:-acquireenglish.curlhairai.com}"
TURN_USER="${TURN_USERNAME:-acquire}"
TURN_PASS="${TURN_PASSWORD:?Set TURN_PASSWORD}"

export DEBIAN_FRONTEND=noninteractive
apt-get install -y coturn

cat >/etc/turnserver.conf <<EOF
listening-port=3478
fingerprint
lt-cred-mech
realm=${REALM}
external-ip=${PUBLIC_IP}/${PRIVATE_IP}
user=${TURN_USER}:${TURN_PASS}
min-port=49152
max-port=49200
no-cli
no-tls
no-dtls
no-multicast-peers
simple-log
EOF

# Enable daemon
sed -i 's/^#\?TURNSERVER_ENABLED=.*/TURNSERVER_ENABLED=1/' /etc/default/coturn
systemctl enable coturn
systemctl restart coturn
systemctl --no-pager --full status coturn | head -20

echo "TURN ready: turn:${REALM}:3478  user=${TURN_USER}"
echo "Open Aliyun SG: UDP/TCP 3478 + UDP 49152-49200"
