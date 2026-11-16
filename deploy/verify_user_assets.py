#!/usr/bin/env python3
from __future__ import annotations

import asyncio
import json
import urllib.request

from sqlalchemy import text

from app.database import engine


async def check_tables() -> None:
    async with engine.begin() as conn:
        rows = await conn.execute(
            text(
                "SELECT table_name FROM information_schema.tables "
                "WHERE table_schema='public' AND table_name IN "
                "('product_skus','orders','order_items','user_entitlements',"
                "'wallet_accounts','wallet_ledger') "
                "ORDER BY table_name"
            )
        )
        names = [r[0] for r in rows]
        print("tables", names)
        assert len(names) == 6, names
        skus = await conn.execute(text("SELECT sku_code FROM product_skus ORDER BY id"))
        print("skus", [r[0] for r in skus])


def req(method: str, url: str, data=None, token: str | None = None):
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    body = None if data is None else json.dumps(data).encode()
    request = urllib.request.Request(url, data=body, headers=headers, method=method)
    with urllib.request.urlopen(request, timeout=20) as resp:
        return resp.status, json.loads(resp.read().decode())


def check_api() -> None:
    base = "http://127.0.0.1:5200"
    _, send = req("POST", f"{base}/api/auth/sms/send", {"phone": "13900006666"})
    code = send.get("debug_code") or "123456"
    _, login = req(
        "POST",
        f"{base}/api/auth/sms/login",
        {"phone": "13900006666", "code": code},
    )
    token = login["access_token"]
    _, assets = req("GET", f"{base}/api/assets", token=token)
    _, skus = req("GET", f"{base}/api/assets/skus", token=token)
    print("assets_ok", assets.get("wallet"), "sku_count", len(skus))
    assert len(skus) >= 1
    _, grant = req(
        "POST",
        f"{base}/api/assets/entitlements/grant",
        {
            "asset_kind": "membership",
            "asset_ref": "pro",
            "source": "promo",
            "duration_days": 30,
        },
        token=token,
    )
    print("grant", grant.get("status"), grant.get("asset_ref"))
    assert grant.get("status") == "active"


if __name__ == "__main__":
    asyncio.run(check_tables())
    check_api()
    print("VERIFY_OK")
