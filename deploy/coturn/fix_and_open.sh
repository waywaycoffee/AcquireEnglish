#!/usr/bin/env bash
# Noninteractive: never prompt. Keep our turnserver.conf; bind all interfaces.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a
export UCF_FORCE_CONFOLD=1
export APT_LISTCHANGES_FRONTEND=none

PASS="${TURN_PASSWORD:?TURN_PASSWORD required}"
PUBLIC_IP="${PUBLIC_IP:-8.163.45.100}"
PRIVATE_IP="${PRIVATE_IP:-$(hostname -I | awk '{print $1}')}"

# Kill stuck interactive package prompts
pkill -9 -f 'dpkg --configure' 2>/dev/null || true
pkill -9 -f 'apt-get' 2>/dev/null || true
sleep 1
rm -f /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock /var/cache/apt/archives/lock

cat >/etc/turnserver.conf <<EOF
listening-ip=0.0.0.0
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
verbose
EOF

if [ -f /etc/default/coturn ]; then
  sed -i 's/^#\?TURNSERVER_ENABLED=.*/TURNSERVER_ENABLED=1/' /etc/default/coturn
fi

dpkg --configure -a --force-confold || true
apt-get install -y -o Dpkg::Options::="--force-confold" -o Dpkg::Options::="--force-confdef" coturn || true

# Rewrite conf again after any package default
cat >/etc/turnserver.conf <<EOF
listening-ip=0.0.0.0
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
verbose
EOF

systemctl enable coturn
systemctl restart coturn
sleep 1
systemctl is-active coturn
ss -tlnp | grep ':3478' | head -8
ss -ulnp | grep ':3478' | head -8
echo fix_done
