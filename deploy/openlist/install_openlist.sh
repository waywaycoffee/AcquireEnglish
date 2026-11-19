#!/usr/bin/env bash
# Install OpenList next to AcquireEnglish API on ECS.
set -euo pipefail

ROOT=/opt/acquireenglish/openlist
API_ENV=/opt/acquireenglish/services/api/.env
NGINX_SNIPPET_SRC="$(cd "$(dirname "$0")/.." && pwd)/nginx/acquireenglish-openlist.conf"

mkdir -p "$ROOT/data"
cp "$(cd "$(dirname "$0")" && pwd)/docker-compose.yml" "$ROOT/docker-compose.yml"
cd "$ROOT"
# Prefer DaoCloud mirror (ECS → docker.io CloudFront often resets).
docker pull docker.m.daocloud.io/openlistteam/openlist:latest || docker compose pull
docker compose up -d

# First boot prints admin password in logs — capture once if not set.
sleep 3
PASS="$(docker logs acquireenglish-openlist 2>&1 | grep -Eo 'password[: ]+[A-Za-z0-9]+' | tail -1 | awk '{print $NF}' || true)"

python3 - <<PY
from pathlib import Path
p = Path("$API_ENV")
text = p.read_text(encoding="utf-8") if p.exists() else ""
extras = {
    "OPENLIST_BASE_URL": "http://127.0.0.1:5244",
    "OPENLIST_PUBLIC_BASE": "https://acquireenglish.curlhairai.com/openlist",
    "OPENLIST_ADMIN_USER": "admin",
}
pass_scraped = """$PASS""".strip()
lines = text.splitlines()
keys = {ln.split("=", 1)[0] for ln in lines if "=" in ln and not ln.strip().startswith("#")}
out = list(lines)
for k, v in extras.items():
    if k not in keys:
        out.append(f"{k}={v}")
if "OPENLIST_ADMIN_PASSWORD" not in keys and pass_scraped:
    out.append(f"OPENLIST_ADMIN_PASSWORD={pass_scraped}")
p.parent.mkdir(parents=True, exist_ok=True)
p.write_text("\n".join(out).rstrip() + "\n", encoding="utf-8")
print("env updated", p)
if "OPENLIST_ADMIN_PASSWORD" not in keys and not pass_scraped:
    print("WARN: set OPENLIST_ADMIN_PASSWORD manually from: docker logs acquireenglish-openlist")
PY

if [ -f "$NGINX_SNIPPET_SRC" ]; then
  cp "$NGINX_SNIPPET_SRC" /etc/nginx/snippets/acquireenglish-openlist.conf
  echo "nginx snippet installed — include snippets/acquireenglish-openlist.conf; then nginx -t && systemctl reload nginx"
fi

systemctl restart acquireenglish-api || true
curl -fsS http://127.0.0.1:5244/ || true
echo
echo "DONE OpenList on :5244"
