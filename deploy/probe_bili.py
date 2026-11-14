import httpx

url = "https://api.bilibili.com/x/web-interface/view"
params = {"bvid": "BV1BsWwz7Eeo"}

cases = {
    "default": None,
    "ua_simple": {"User-Agent": "Mozilla/5.0"},
    "current": {
        "User-Agent": (
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
            "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
        ),
        "Referer": "https://www.bilibili.com",
        "Accept": "application/json, text/plain, */*",
    },
    "chrome_no_referer": {
        "User-Agent": (
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
            "(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"
        ),
        "Accept": "application/json",
    },
    "bili_app": {
        "User-Agent": "Mozilla/5.0 BiliDroid/7.0.0 (bbcallen@gmail.com)",
        "Referer": "https://www.bilibili.com",
    },
    "curl_ua": {"User-Agent": "curl/8.5.0"},
}

for name, headers in cases.items():
    try:
        r = httpx.get(url, params=params, headers=headers, timeout=20.0)
        snippet = r.text[:60].replace("\n", " ")
        print(f"{name}: {r.status_code} {snippet}")
    except Exception as exc:
        print(f"{name}: ERR {exc}")
