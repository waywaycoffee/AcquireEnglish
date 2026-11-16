#!/usr/bin/env bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a
export UCF_FORCE_CONFOLD=1
PASS="${TURN_PASSWORD:?TURN_PASSWORD required}"
PUBLIC_IP="${PUBLIC_IP:-8.163.45.100}"
PRIVATE_IP="${PRIVATE_IP:-$(hostname -I | awk '{print $1}')}"

TS=$(date +%Y%m%d%H%M%S)
cp -a /etc/apt/sources.list "/etc/apt/sources.list.bak.${TS}" 2>/dev/null || true
mkdir -p /etc/apt/sources.list.d/disabled
mv /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/disabled/ 2>/dev/null || true

. /etc/os-release
CODENAME="${VERSION_CODENAME:-noble}"
echo "codename=${CODENAME} public=${PUBLIC_IP} private=${PRIVATE_IP}"

cat >/etc/apt/sources.list <<EOF
deb http://archive.ubuntu.com/ubuntu ${CODENAME} main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu ${CODENAME}-updates main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu ${CODENAME}-security main restricted universe multiverse
EOF

apt-get update -o Acquire::Retries=3
DEBIAN_FRONTEND=noninteractive apt-get install -y coturn

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
systemctl enable coturn || true
systemctl restart coturn
sleep 1
systemctl --no-pager --full status coturn | head -25
ss -ulnp | grep 3478 || true
ss -tlnp | grep 3478 || true
echo "coturn install done"
