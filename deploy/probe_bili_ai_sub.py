"""Probe Bilibili AI subtitle endpoints for BV1BsWwz7Eeo."""
import json
import re
import httpx

bvid = "BV1BsWwz7Eeo"
ua_curl = {"User-Agent": "curl/8.5.0", "Accept": "*/*"}
ua_browser = {
    "User-Agent": (
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
        "(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"
    ),
    "Referer": "https://www.bilibili.com",
    "Accept": "application/json, text/plain, */*",
}

with httpx.Client(timeout=30.0, follow_redirects=True) as c:
    view = c.get(
        "https://api.bilibili.com/x/web-interface/view",
        params={"bvid": bvid},
        headers=ua_curl,
    ).json()["data"]
    aid = view["aid"]
    cid = view["cid"]
    print("aid", aid, "cid", cid)

    endpoints = [
        ("v2 curl", "https://api.bilibili.com/x/player/v2", {"bvid": bvid, "cid": cid}, ua_curl),
        ("v2 browser", "https://api.bilibili.com/x/player/v2", {"bvid": bvid, "cid": cid}, ua_browser),
        ("wbi curl", "https://api.bilibili.com/x/player/wbi/v2", {"bvid": bvid, "cid": cid}, ua_curl),
        (
            "online/v2",
            "https://api.bilibili.com/x/player/online/total",
            {"bvid": bvid, "cid": cid},
            ua_curl,
        ),
    ]
    for name, url, params, headers in endpoints:
        r = c.get(url, params=params, headers=headers)
        try:
            root = r.json()
        except Exception:
            print(name, r.status_code, r.text[:80])
            continue
        data = root.get("data") or {}
        sub = data.get("subtitle") or {}
        print(
            name,
            "http",
            r.status_code,
            "code",
            root.get("code"),
            "need_login",
            data.get("need_login_subtitle"),
            "subs",
            len(sub.get("subtitles") or []),
            "keys_has_ai",
            any("ai" in str(k).lower() for k in data.keys()),
        )
        # dump interesting keys
        for k in sorted(data.keys()):
            if "sub" in k.lower() or "ai" in k.lower() or "caption" in k.lower():
                val = data[k]
                if isinstance(val, (dict, list)):
                    print(" ", k, json.dumps(val, ensure_ascii=False)[:200])
                else:
                    print(" ", k, val)

    # Try common AI subtitle prod URL patterns from open-source notes
    # Some clients call: https://api.bilibili.com/x/player/v2 then subtitle_url
    # AI list sometimes at: https://aisubtitle.hdslb.com/bfs/ai_subtitle/prod/{bvid?}
    for url in [
        f"https://api.bilibili.com/x/player.so?id={cid}&aid={aid}&bvid={bvid}",
        f"https://api.bilibili.com/x/v2/dm/view?aid={aid}&oid={cid}&type=1",
    ]:
        r = c.get(url, headers=ua_curl)
        text = r.text[:150].replace("\n", " ")
        print("extra", url.split("bilibili.com")[-1][:50], r.status_code, text)
