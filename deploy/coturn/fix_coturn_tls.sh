#!/usr/bin/env bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

PASS="${TURN_PASSWORD:?}"
PUBLIC_IP="${PUBLIC_IP:-8.163.45.100}"
PRIVATE_IP="${PRIVATE_IP:-$(hostname -I | awk '{print $1}')}"
TURN_HOST="${TURN_HOST:-turn.curlhairai.com}"
CERT="/etc/letsencrypt/live/${TURN_HOST}/fullchain.pem"
KEY="/etc/letsencrypt/live/${TURN_HOST}/privkey.pem"

systemctl stop coturn || true
pkill -9 turnserver 2>/dev/null || true
sleep 1

# TLS-only public path on 5349; keep UDP 3478 for Tailscale/LAN debug
cat >/etc/turnserver.conf <<EOF
listening-ip=127.0.0.1
listening-ip=${PRIVATE_IP}
listening-port=3478
tls-listening-port=5349
fingerprint
lt-cred-mech
realm=${TURN_HOST}
external-ip=${PUBLIC_IP}/${PRIVATE_IP}
user=acquire:${PASS}
min-port=49152
max-port=49200
cert=${CERT}
pkey=${KEY}
no-tlsv1
no-tlsv1_1
no-cli
no-dtls
no-multicast-peers
simple-log
verbose
EOF

# Allow coturn to read Let's Encrypt privkey (Debian/Ubuntu: turnserver in turnserver group)
if getent group turnserver >/dev/null; then
  chgrp turnserver "$KEY" 2>/dev/null || true
  chmod 640 "$KEY" 2>/dev/null || true
  # Prefer ssl-cert group pattern
  if getent group ssl-cert >/dev/null; then
    chgrp ssl-cert "$KEY" || true
    usermod -a -G ssl-cert turnserver 2>/dev/null || true
    chmod 640 "$KEY" || true
  fi
fi
# Also symlink readable copies for turnserver user
mkdir -p /etc/coturn/certs
cp -f "$CERT" /etc/coturn/certs/fullchain.pem
cp -f "$KEY" /etc/coturn/certs/privkey.pem
chown -R turnserver:turnserver /etc/coturn/certs
chmod 640 /etc/coturn/certs/privkey.pem
chmod 644 /etc/coturn/certs/fullchain.pem
sed -i "s|^cert=.*|cert=/etc/coturn/certs/fullchain.pem|" /etc/turnserver.conf
sed -i "s|^pkey=.*|pkey=/etc/coturn/certs/privkey.pem|" /etc/turnserver.conf

systemctl start coturn
sleep 1
systemctl is-active coturn
ss -tlnp | grep -E '3478|5349' || true
ss -ulnp | grep 3478 | head -3 || true
# Local TLS handshake smoke
timeout 3 openssl s_client -connect 127.0.0.1:5349 -servername "${TURN_HOST}" </dev/null 2>/dev/null | grep -E 'subject=|Verify return' | head -5 || true
# Through nginx SNI
timeout 3 openssl s_client -connect 127.0.0.1:443 -servername "${TURN_HOST}" </dev/null 2>/dev/null | grep -E 'subject=|Verify return' | head -5 || true
echo coturn_tls_fix_done
