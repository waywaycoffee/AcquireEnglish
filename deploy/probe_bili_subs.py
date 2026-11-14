import httpx

headers = {"User-Agent": "curl/8.5.0"}
bvid = "BV1BsWwz7Eeo"
with httpx.Client(headers=headers, timeout=30.0) as c:
    view = c.get(
        "https://api.bilibili.com/x/web-interface/view", params={"bvid": bvid}
    ).json()["data"]
    pages = view["pages"]
    found = 0
    for p in pages[:12]:
        r = c.get(
            "https://api.bilibili.com/x/player/v2",
            params={"bvid": bvid, "cid": p["cid"]},
        ).json()
        data = r.get("data") or {}
        subs = ((data.get("subtitle") or {}).get("subtitles")) or []
        need = data.get("need_login_subtitle")
        print(
            f"P{p['page']} {p['part'][:28]!r} need_login={need} subs={len(subs)}"
        )
        if subs:
            found += 1
            print(
                " ",
                [
                    (s.get("lan"), s.get("lan_doc"), (s.get("subtitle_url") or "")[:70])
                    for s in subs
                ],
            )
    print("found_with_subs_in_first12", found)
