import httpx

bvid = "BV1BsWwz7Eeo"
headers = {"User-Agent": "curl/8.5.0", "Accept": "*/*"}

# Optional cookie from server env / prefs not loaded here; try anonymous first.
with httpx.Client(headers=headers, timeout=30.0, follow_redirects=True) as c:
    view = c.get(
        "https://api.bilibili.com/x/web-interface/view", params={"bvid": bvid}
    ).json()
    print("view_code", view.get("code"), view.get("message"))
    data = view.get("data") or {}
    pages = data.get("pages") or []
    print("title", data.get("title"))
    print("pages", len(pages))
    cid = data.get("cid") or (pages[0].get("cid") if pages else None)
    print("cid", cid)

    for name, params in [
        ("player_v2", {"bvid": bvid, "cid": cid}),
        ("player_v2_aid", {"aid": data.get("aid"), "cid": cid}),
    ]:
        r = c.get("https://api.bilibili.com/x/player/v2", params=params).json()
        pdata = r.get("data") or {}
        sub = (pdata.get("subtitle") or {}).get("subtitles") or []
        print(
            name,
            "code",
            r.get("code"),
            "need_login",
            pdata.get("need_login_subtitle"),
            "subs",
            len(sub),
            [(s.get("lan"), s.get("lan_doc")) for s in sub[:8]],
        )

    # Also check first 3 parts
    for p in pages[:3]:
        r = c.get(
            "https://api.bilibili.com/x/player/v2",
            params={"bvid": bvid, "cid": p["cid"]},
        ).json()
        pdata = r.get("data") or {}
        sub = (pdata.get("subtitle") or {}).get("subtitles") or []
        print(
            f"P{p['page']}",
            p["part"][:28],
            "need_login",
            pdata.get("need_login_subtitle"),
            "subs",
            len(sub),
        )
