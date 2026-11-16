#!/usr/bin/env bash
# CurlHair-style: only 80/443 public. TURN over TLS on turn.<domain>:443 via nginx stream SNI.
# Fully noninteractive — auto-confirm all package/cert prompts.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a
export UCF_FORCE_CONFOLD=1
export APT_LISTCHANGES_FRONTEND=none

PASS="${TURN_PASSWORD:?TURN_PASSWORD required}"
PUBLIC_IP="${PUBLIC_IP:-8.163.45.100}"
PRIVATE_IP="${PRIVATE_IP:-$(hostname -I | awk '{print $1}')}"
TURN_HOST="${TURN_HOST:-turn.curlhairai.com}"
WEB_PORT=8443

echo "== DNS must already point ${TURN_HOST} -> ${PUBLIC_IP}"

# 1) Cert for TURN host (HTTP-01 on :80)
certbot certonly --nginx -d "${TURN_HOST}" --non-interactive --agree-tos \
  --register-unsafely-without-email --keep-until-expiring || \
certbot certonly --webroot -w /var/www/html -d "${TURN_HOST}" --non-interactive --agree-tos \
  --register-unsafely-without-email --keep-until-expiring

CERT="/etc/letsencrypt/live/${TURN_HOST}/fullchain.pem"
KEY="/etc/letsencrypt/live/${TURN_HOST}/privkey.pem"
test -f "$CERT" && test -f "$KEY"

# 2) coturn with TLS on 5349 (loopback); plain 3478 for local/Tailscale
cat >/etc/turnserver.conf <<EOF
listening-ip=0.0.0.0
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
no-cli
no-dtls
no-multicast-peers
simple-log
verbose
EOF
sed -i 's/^#\?TURNSERVER_ENABLED=.*/TURNSERVER_ENABLED=1/' /etc/default/coturn
systemctl enable coturn
systemctl restart coturn

# 3) Move site listen 443 -> 8443 (idempotent)
python3 - <<'PY'
from pathlib import Path
import re
root = Path("/etc/nginx/sites-enabled")
for p in root.iterdir():
    if not p.is_file():
        continue
    text = p.read_text(encoding="utf-8", errors="ignore")
    orig = text
    # listen 443 ssl -> 127.0.0.1:8443 ssl (keep certbot managed lines working)
    text = re.sub(
        r"(?m)^(\s*listen\s+)(\[::\]:)?443(\s+ssl.*)$",
        lambda m: f"{m.group(1)}127.0.0.1:8443{m.group(3)}" if not m.group(2)
        else f"{m.group(1)}[::1]:8443{m.group(3)}",
        text,
    )
    # also plain listen 443;
    text = re.sub(
        r"(?m)^(\s*listen\s+)(\[::\]:)?443(\s*;)$",
        lambda m: f"{m.group(1)}127.0.0.1:8443{m.group(3)}" if not m.group(2)
        else f"{m.group(1)}[::1]:8443{m.group(3)}",
        text,
    )
    if text != orig:
        p.write_text(text, encoding="utf-8")
        print("patched", p)
PY

# 4) stream SNI mux on public 443
mkdir -p /etc/nginx/streams-enabled
cat >/etc/nginx/streams-enabled/turn-sni.conf <<EOF
map \$ssl_preread_server_name \$ae_upstream {
    ${TURN_HOST}           ae_turn;
    default                ae_https;
}
upstream ae_turn  { server 127.0.0.1:5349; }
upstream ae_https { server 127.0.0.1:${WEB_PORT}; }
server {
    listen 443;
    listen [::]:443;
    proxy_connect_timeout 10s;
    proxy_timeout 3600s;
    ssl_preread on;
    proxy_pass \$ae_upstream;
}
EOF

# Ensure nginx.conf includes streams
if ! grep -q 'streams-enabled' /etc/nginx/nginx.conf; then
  if grep -q '^http {' /etc/nginx/nginx.conf; then
    sed -i '/^http {/i stream {\n    include /etc/nginx/streams-enabled/*.conf;\n}\n' /etc/nginx/nginx.conf
  else
    cat >>/etc/nginx/nginx.conf <<'EOF'

stream {
    include /etc/nginx/streams-enabled/*.conf;
}
EOF
  fi
fi

nginx -t
systemctl reload nginx
systemctl restart coturn
sleep 1
systemctl is-active coturn
ss -tlnp | grep -E ':443|:8443|:5349|:3478' | head -20
echo setup_turn_443_done
