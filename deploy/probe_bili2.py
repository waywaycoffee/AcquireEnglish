import httpx

headers = {"User-Agent": "curl/8.5.0"}
params = {"bvid": "BV1BsWwz7Eeo"}
with httpx.Client(headers=headers, timeout=25.0, follow_redirects=True) as client:
    view = client.get("https://api.bilibili.com/x/web-interface/view", params=params)
    print("view", view.status_code, view.json().get("code"), view.json().get("data", {}).get("title", "")[:40])
    data = view.json()["data"]
    bvid = data["bvid"]
    cid = data.get("cid") or data["pages"][0]["cid"]
    player = client.get(
        "https://api.bilibili.com/x/player/v2",
        params={"bvid": bvid, "cid": cid},
    )
    print("player", player.status_code, player.json().get("code"))
    subs = (((player.json().get("data") or {}).get("subtitle") or {}).get("subtitles")) or []
    print("subs", len(subs), [s.get("lan") for s in subs[:5]])
    if subs:
        sub_url = subs[0].get("subtitle_url") or ""
        if sub_url.startswith("//"):
            sub_url = "https:" + sub_url
        sub = client.get(sub_url)
        print("sub", sub.status_code, sub.headers.get("content-type"), len(sub.text))
