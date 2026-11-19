#!/usr/bin/env bash
# Install OpenList binary (not Docker) next to AcquireEnglish API on ECS.
# OpenList v4 only auto-creates admin when OPENLIST_ADMIN_PASSWORD is set.
set -euo pipefail

ROOT=/opt/acquireenglish/openlist
API_ENV=/opt/acquireenglish/services/api/.env
VERSION="${OPENLIST_VERSION:-v4.2.10}"
TGZ_URL="${OPENLIST_TGZ_URL:-https://github.com/OpenListTeam/OpenList/releases/download/${VERSION}/openlist-linux-amd64.tar.gz}"
NGINX_SNIPPET_SRC="$(cd "$(dirname "$0")/.." && pwd)/nginx/acquireenglish-openlist.conf"

mkdir -p "$ROOT/data"
cd "$ROOT"

if [ ! -x "$ROOT/openlist" ]; then
  if [ -f /tmp/openlist-linux-amd64.tar.gz ]; then
    tar -xzf /tmp/openlist-linux-amd64.tar.gz -C "$ROOT"
  else
    curl -fL --retry 3 --max-time 300 -o /tmp/openlist-linux-amd64.tar.gz "$TGZ_URL"
    tar -xzf /tmp/openlist-linux-amd64.tar.gz -C "$ROOT"
  fi
  chmod +x "$ROOT/openlist"
fi

PASS_FILE=/opt/acquireenglish/openlist/admin.pass
if [ ! -s "$PASS_FILE" ]; then
  openssl rand -hex 12 > "$PASS_FILE"
  chmod 600 "$PASS_FILE"
fi
PASS=$(cat "$PASS_FILE")

cat > /etc/systemd/system/acquireenglish-openlist.service <<UNIT
[Unit]
Description=AcquireEnglish OpenList
After=network.target

[Service]
WorkingDirectory=/opt/acquireenglish/openlist
Environment=OPENLIST_ADMIN_PASSWORD=$PASS
ExecStart=/opt/acquireenglish/openlist/openlist server --data /opt/acquireenglish/openlist/data
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable --now acquireenglish-openlist
sleep 2
systemctl is-active acquireenglish-openlist

python3 - <<PY
from pathlib import Path
p = Path("$API_ENV")
text = p.read_text(encoding="utf-8") if p.exists() else ""
pw = Path("$PASS_FILE").read_text().strip()
extras = {
    "OPENLIST_BASE_URL": "http://127.0.0.1:5244",
    "OPENLIST_PUBLIC_BASE": "https://acquireenglish.curlhairai.com/openlist",
    "OPENLIST_ADMIN_USER": "admin",
    "OPENLIST_ADMIN_PASSWORD": pw,
}
lines = text.splitlines()
keys = {ln.split("=", 1)[0] for ln in lines if "=" in ln and not ln.strip().startswith("#")}
out = list(lines)
for k, v in extras.items():
    if k in keys:
        out = [ln if not ln.startswith(k + "=") else f"{k}={v}" for ln in out]
    else:
        out.append(f"{k}={v}")
p.parent.mkdir(parents=True, exist_ok=True)
p.write_text("\n".join(out).rstrip() + "\n", encoding="utf-8")
print("env ok", p)
PY

if [ -f "$NGINX_SNIPPET_SRC" ]; then
  cp "$NGINX_SNIPPET_SRC" /etc/nginx/snippets/acquireenglish-openlist.conf
fi
if [ -f /etc/nginx/sites-enabled/acquireenglish ] && \
   ! grep -q acquireenglish-openlist.conf /etc/nginx/sites-enabled/acquireenglish; then
  sed -i '/include snippets\/acquireenglish-ollama.conf;/a\    include snippets/acquireenglish-openlist.conf;' \
    /etc/nginx/sites-enabled/acquireenglish
fi
nginx -t
systemctl reload nginx
systemctl restart acquireenglish-api
sleep 2
curl -fsS http://127.0.0.1:5200/api/health; echo
curl -fsS -o /dev/null -w "openlist=%{http_code}\n" http://127.0.0.1:5244/
echo "DONE OpenList binary on :5244"
