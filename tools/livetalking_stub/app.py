"""Minimal LiveTalking-compatible HTTP stub for coach soft-fail verification.
Endpoints: GET /  POST /human  POST /offer (stub answer)
"""
from __future__ import annotations
from aiohttp import web
import json

async def index(request: web.Request) -> web.Response:
    return web.json_response({"service": "livetalking-stub", "ok": True, "port": 8010})

async def human(request: web.Request) -> web.Response:
    try:
        body = await request.json()
    except Exception:
        body = {}
    text = (body.get("text") or "")[:200]
    print(f"[human] type={body.get('type')} text_len={len(text)}")
    return web.json_response({"code": 0, "data": "ok", "echo": text})

async def offer(request: web.Request) -> web.Response:
    # Not a real WebRTC answer — keeps connect soft-failable
    return web.json_response({"type": "answer", "sdp": "", "sessionid": 0, "error": "stub_no_webrtc"})

app = web.Application()
app.router.add_get("/", index)
app.router.add_post("/human", human)
app.router.add_get("/human", human)
app.router.add_post("/offer", offer)

if __name__ == "__main__":
    web.run_app(app, host="0.0.0.0", port=8010)
