import httpx

headers = {"User-Agent": "curl/8.5.0", "Accept": "*/*"}
bvid = "BV1BsWwz7Eeo"
with httpx.Client(headers=headers, timeout=30.0) as c:
    view = c.get(
        "https://api.bilibili.com/x/web-interface/view", params={"bvid": bvid}
    ).json()["data"]
    cid = view["pages"][0]["cid"]
    r = c.get(
        "https://api.bilibili.com/x/player/playurl",
        params={"bvid": bvid, "cid": cid, "fnval": 16, "fourk": 1},
    )
    print("status", r.status_code)
    data = r.json()
    print("code", data.get("code"), data.get("message"))
    dash = ((data.get("data") or {}).get("dash") or {})
    audio = dash.get("audio") or []
    print("audio_streams", len(audio))
    if audio:
        print("first", audio[0].get("id"), (audio[0].get("baseUrl") or "")[:80])
