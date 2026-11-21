#!/usr/bin/env python3
"""One-shot probe of /api/admin/usage/platform (masks secrets)."""
from __future__ import annotations

import json
import os
import urllib.request
from pathlib import Path


def main() -> None:
    env = Path("/opt/acquireenglish/services/api/.env")
    token = ""
    for line in env.read_text(encoding="utf-8", errors="replace").splitlines():
        if line.startswith("ADMIN_API_TOKEN="):
            token = line.split("=", 1)[1].strip().strip("'").strip('"')
            break
    req = urllib.request.Request(
        "http://127.0.0.1:5200/api/admin/usage/platform",
        headers={"X-Admin-Token": token},
    )
    with urllib.request.urlopen(req, timeout=90) as r:
        data = json.loads(r.read().decode())
    print(
        json.dumps(
            {
                "ok": data.get("ok"),
                "billing_cycle": data.get("billing_cycle"),
                "configured_count": data.get("configured_count"),
                "summary": data.get("summary"),
                "keys": [
                    {
                        "id": k.get("id"),
                        "label": k.get("label"),
                        "configured": k.get("configured"),
                        "key_label": k.get("key_label"),
                        "env": k.get("env"),
                        "source": k.get("source"),
                    }
                    for k in data.get("keys") or []
                ],
                "tencent": {
                    "ok": (data.get("tencent") or {}).get("ok"),
                    "error": ((data.get("tencent") or {}).get("error") or "")[:160],
                    "items": len((data.get("tencent") or {}).get("items") or []),
                },
                "aliyun": {
                    "ok": (data.get("aliyun") or {}).get("ok"),
                    "error": ((data.get("aliyun") or {}).get("error") or "")[:160],
                    "balance": (data.get("aliyun") or {}).get("balance_cny"),
                    "products": {
                        code: {
                            "pretax_cny": (prod or {}).get("pretax_cny"),
                            "count": (prod or {}).get("count"),
                        }
                        for code, prod in ((data.get("aliyun") or {}).get("products") or {}).items()
                    },
                },
                "livekit": {
                    "configured": (data.get("livekit") or {}).get("configured"),
                    "project_hint": (data.get("livekit") or {}).get("project_hint"),
                },
                "gpu": data.get("gpu"),
                "deepgram": data.get("deepgram"),
                "deepseek": data.get("deepseek"),
            },
            ensure_ascii=False,
            indent=2,
        )
    )


if __name__ == "__main__":
    main()
