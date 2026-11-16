#!/usr/bin/env bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a
export UCF_FORCE_CONFOLD=1

# Install stream module (auto-confirm)
apt-get install -y -o Dpkg::Options::="--force-confold" libnginx-mod-stream || \
  apt-get install -y -o Dpkg::Options::="--force-confold" nginx-module-stream || true

ls -la /etc/nginx/modules-enabled/ || true
ls /usr/lib/nginx/modules/ 2>/dev/null | head || true
ls /usr/share/nginx/modules/ 2>/dev/null | head || true

# If package didn't drop a modules-enabled snippet, load explicitly
if [ -f /usr/lib/nginx/modules/ngx_stream_module.so ]; then
  echo 'load_module /usr/lib/nginx/modules/ngx_stream_module.so;' \
    >/etc/nginx/modules-enabled/50-mod-stream.conf
elif [ -f /usr/share/nginx/modules/ngx_stream_module.so ]; then
  echo 'load_module modules/ngx_stream_module.so;' \
    >/etc/nginx/modules-enabled/50-mod-stream.conf
fi

mkdir -p /etc/nginx/streams-enabled
TURN_HOST="${TURN_HOST:-turn.curlhairai.com}"
cat >/etc/nginx/streams-enabled/turn-sni.conf <<EOF
map \$ssl_preread_server_name \$ae_upstream {
    ${TURN_HOST}           ae_turn;
    default                ae_https;
}
upstream ae_turn  { server 127.0.0.1:5349; }
upstream ae_https { server 127.0.0.1:8443; }
server {
    listen 443;
    listen [::]:443;
    proxy_connect_timeout 10s;
    proxy_timeout 3600s;
    ssl_preread on;
    proxy_pass \$ae_upstream;
}
EOF

if nginx -t; then
  systemctl reload nginx
  echo nginx_ok
else
  echo nginx_test_failed — restoring listen 443 on sites
  # Emergency rollback: put sites back on 443, remove stream block
  python3 - <<'PY'
from pathlib import Path
import re
root = Path("/etc/nginx/sites-enabled")
for p in root.iterdir():
    if not p.is_file():
        continue
    text = p.read_text(encoding="utf-8", errors="ignore")
    text2 = text.replace("127.0.0.1:8443", "443").replace("[::1]:8443", "[::]:443")
    if text2 != text:
        p.write_text(text2, encoding="utf-8")
        print("restored", p)
conf = Path("/etc/nginx/nginx.conf")
c = conf.read_text(encoding="utf-8", errors="ignore")
c2 = re.sub(r"\nstream \{\n    include /etc/nginx/streams-enabled/\*\.conf;\n\}\n", "\n", c)
if c2 != c:
    conf.write_text(c2, encoding="utf-8")
    print("removed stream block")
PY
  nginx -t && systemctl reload nginx
  echo rolled_back
  exit 1
fi

ss -tlnp | grep -E ':443|:8443|:5349' | head -20
curl -sS -o /dev/null -w 'https_ae:%{http_code}\n' --max-time 8 https://acquireenglish.curlhairai.com/livetalking/index.html || true
curl -sS -o /dev/null -w 'https_api:%{http_code}\n' --max-time 8 https://api.curlhairai.com/ || true
systemctl is-active coturn
echo fix_stream_done
