#!/usr/bin/env bash
set -euo pipefail
API=/opt/acquireenglish/services/api
SRC=/tmp/ae_assets_sync

# Ensure DailyFeedItemOut exists in schemas before restart
python3 - <<'PY'
from pathlib import Path
p = Path("/opt/acquireenglish/services/api/app/schemas.py")
text = p.read_text(encoding="utf-8")
needle = "class DailyFeedItemOut"
if needle not in text:
    block = '''

class DailyFeedItemOut(BaseModel):
    id: str
    bvid: str
    title: str
    author: str | None = None
    coverUrl: str | None = None
    durationSec: int | None = None
    watchUrl: str
    description: str | None = None
    tags: list[str] = []
    source: str = "bilibili"
'''
    # Insert before asset schemas if present, else append
    marker = "# --- User assets"
    if marker in text:
        text = text.replace(marker, block + "\n" + marker, 1)
    else:
        text = text.rstrip() + block + "\n"
    p.write_text(text, encoding="utf-8")
    print("added DailyFeedItemOut")
else:
    print("DailyFeedItemOut already present")
PY

# Keep shared_subtitles router if present on disk
if [ -f "$API/app/routers/shared_subtitles.py" ]; then
  if ! grep -q 'shared_subtitles' "$API/app/main.py"; then
    python3 - <<'PY'
from pathlib import Path
p = Path("/opt/acquireenglish/services/api/app/main.py")
t = p.read_text(encoding="utf-8")
if "shared_subtitles" not in t:
    t = t.replace(
        "from app.routers import (",
        "from app.routers import (\n    shared_subtitles,",
        1,
    )
    t = t.replace(
        "app.include_router(assets.router, prefix=\"/api\")",
        "app.include_router(assets.router, prefix=\"/api\")\napp.include_router(shared_subtitles.router, prefix=\"/api\")",
        1,
    )
    # fallback if assets line missing
    if "shared_subtitles.router" not in t:
        t = t.replace(
            "app.include_router(livekit.router, prefix=\"/api\")",
            "app.include_router(livekit.router, prefix=\"/api\")\napp.include_router(shared_subtitles.router, prefix=\"/api\")",
            1,
        )
    p.write_text(t, encoding="utf-8")
    print("wired shared_subtitles")
else:
    print("shared_subtitles already wired")
PY
  fi
fi

cd "$API"
# shellcheck disable=SC1091
source .venv/bin/activate
python - <<'PY'
from app.main import app
paths = sorted({getattr(r, "path", "") for r in app.routes})
asset = [p for p in paths if "/assets" in p]
print("app_ok", app.title)
print("asset_routes", asset)
assert any(p.startswith("/api/assets") for p in asset), asset
from app.schemas import DailyFeedItemOut  # noqa: F401
print("schemas_ok")
PY

systemctl restart acquireenglish-api
sleep 2
systemctl is-active acquireenglish-api
curl -fsS http://127.0.0.1:5200/api/health; echo
curl -fsS https://acquireenglish.curlhairai.com/api/health; echo

python - <<'PY'
import asyncio
from sqlalchemy import text
from app.database import engine

async def main():
    async with engine.begin() as conn:
        rows = await conn.execute(text(
            "SELECT table_name FROM information_schema.tables "
            "WHERE table_schema='public' AND table_name IN "
            "('product_skus','orders','order_items','user_entitlements',"
            "'wallet_accounts','wallet_ledger') "
            "ORDER BY table_name"
        ))
        names = [r[0] for r in rows]
        print("tables", names)
        assert len(names) == 6, names
        skus = await conn.execute(text("SELECT sku_code FROM product_skus ORDER BY id"))
        print("skus", [r[0] for r in skus])

asyncio.run(main())
PY

# Auth smoke: sms mock login + assets
python - <<'PY'
import json, urllib.request

def req(method, url, data=None, token=None):
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    body = None if data is None else json.dumps(data).encode()
    r = urllib.request.Request(url, data=body, headers=headers, method=method)
    with urllib.request.urlopen(r, timeout=20) as resp:
        return resp.status, json.loads(resp.read().decode())

base = "http://127.0.0.1:5200"
st, send = req("POST", f"{base}/api/auth/sms/send", {"phone": "13900006666"})
assert st == 200, send
code = send.get("debug_code") or "123456"
st, login = req("POST", f"{base}/api/auth/sms/login", {"phone": "13900006666", "code": code})
assert st == 200, login
token = login["access_token"]
st, assets = req("GET", f"{base}/api/assets", token=token)
assert st == 200, assets
st, skus = req("GET", f"{base}/api/assets/skus", token=token)
assert st == 200 and len(skus) >= 1, skus
print("api_assets_ok", "skus", len(skus), "wallet", assets.get("wallet"))
# public openapi has assets
with urllib.request.urlopen(f"{base}/openapi.json", timeout=10) as resp:
    paths = json.load(resp)["paths"]
print("openapi_assets", [p for p in sorted(paths) if "assets" in p])
PY

echo DEPLOY_ASSETS_DONE
