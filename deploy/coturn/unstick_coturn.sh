#!/usr/bin/env bash
set -euo pipefail
PASS="${TURN_PASSWORD:?TURN_PASSWORD required}"
PUBLIC_IP="${PUBLIC_IP:-8.163.45.100}"
PRIVATE_IP="${PRIVATE_IP:-$(hostname -I | awk '{print $1}')}"

pkill -9 -f 'dpkg --configure' 2>/dev/null || true
pkill -9 -f 'apt-get' 2>/dev/null || true
sleep 1
rm -f /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock /var/cache/apt/archives/lock

# Our config first so force-confold keeps it
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

export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a
apt-get install -y -o Dpkg::Options::="--force-confold" coturn
dpkg --configure -a || true

if [ -f /etc/default/coturn ]; then
  sed -i 's/^#\?TURNSERVER_ENABLED=.*/TURNSERVER_ENABLED=1/' /etc/default/coturn
fi
# rewrite our conf again in case package overwrote
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

systemctl enable coturn
systemctl restart coturn
sleep 1
systemctl is-active coturn
ss -ulnp | grep 3478 || true
ss -tlnp | grep 3478 || true
dpkg -l coturn | tail -1
echo unstick_done
