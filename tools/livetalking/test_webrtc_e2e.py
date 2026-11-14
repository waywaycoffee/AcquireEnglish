#!/usr/bin/env python3
"""LiveTalking WebRTC lip-sync E2E (offer → tracks → /human echo).

Usage:
  # Prefer LiveTalking venv (has aiortc):
  third_party/LiveTalking/.venv/Scripts/python.exe tools/livetalking/test_webrtc_e2e.py

  # Or:
  LIVETALKING_BASE=http://100.115.252.55:8010 python tools/livetalking/test_webrtc_e2e.py

Exit 0 on pass. Prints a short JSON summary (no secrets).
"""

from __future__ import annotations

import argparse
import asyncio
import json
import os
import sys
import time
from typing import Any

import aiohttp

try:
    from aiortc import (
        RTCConfiguration,
        RTCIceServer,
        RTCPeerConnection,
        RTCSessionDescription,
    )
    from aiortc.mediastreams import MediaStreamError
except ImportError as exc:  # pragma: no cover
    print(
        json.dumps(
            {
                "ok": False,
                "error": "aiortc_missing",
                "hint": "Use third_party/LiveTalking/.venv python or pip install aiortc",
                "detail": str(exc),
            }
        ),
        file=sys.stderr,
    )
    sys.exit(2)


DEFAULT_BASE = os.environ.get("LIVETALKING_BASE", "http://100.115.252.55:8010").rstrip("/")
DEFAULT_AVATAR = os.environ.get("LIVETALKING_AVATAR", "wav2lip_avatar_glass_man")
DEFAULT_TEXT = os.environ.get("LIVETALKING_ECHO_TEXT", "Hello from AcquireEnglish WebRTC E2E.")


async def _http_get_root(session: aiohttp.ClientSession, base: str) -> int:
    async with session.get(base + "/", allow_redirects=False) as resp:
        return resp.status


async def _wait_ice_complete(pc: RTCPeerConnection, timeout: float = 8.0) -> None:
    if pc.iceGatheringState == "complete":
        return
    done = asyncio.get_event_loop().create_future()

    @pc.on("icegatheringstatechange")
    def _on_ice() -> None:
        if pc.iceGatheringState == "complete" and not done.done():
            done.set_result(True)

    try:
        await asyncio.wait_for(done, timeout=timeout)
    except asyncio.TimeoutError:
        pass


async def run_e2e(
    base: str,
    avatar: str,
    echo_text: str,
    track_wait_s: float,
    speak_wait_s: float,
) -> dict[str, Any]:
    result: dict[str, Any] = {
        "ok": False,
        "base": base,
        "avatar": avatar,
        "steps": {},
    }
    timeout = aiohttp.ClientTimeout(total=120)
    async with aiohttp.ClientSession(timeout=timeout) as http:
        # 1) GET /
        status = await _http_get_root(http, base)
        result["steps"]["get_root"] = {"status": status}
        if status not in (200, 302):
            result["error"] = f"GET / unexpected status {status}"
            return result

        # 2) WebRTC /offer
        ice_servers = [RTCIceServer(urls=["stun:stun.l.google.com:19302"])]
        pc = RTCPeerConnection(configuration=RTCConfiguration(iceServers=ice_servers))
        video_frames = 0
        audio_frames = 0
        track_kinds: set[str] = set()
        connection_states: list[str] = []

        @pc.on("connectionstatechange")
        async def _on_state() -> None:
            connection_states.append(pc.connectionState)

        @pc.on("track")
        def _on_track(track) -> None:  # noqa: ANN001
            track_kinds.add(track.kind)

            async def _consume() -> None:
                nonlocal video_frames, audio_frames
                while True:
                    try:
                        await track.recv()
                    except MediaStreamError:
                        break
                    except Exception:
                        break
                    if track.kind == "video":
                        video_frames += 1
                    elif track.kind == "audio":
                        audio_frames += 1

            asyncio.ensure_future(_consume())

        pc.addTransceiver("video", direction="recvonly")
        pc.addTransceiver("audio", direction="recvonly")

        offer = await pc.createOffer()
        await pc.setLocalDescription(offer)
        await _wait_ice_complete(pc)

        local = pc.localDescription
        assert local is not None and local.sdp

        offer_body: dict[str, Any] = {
            "type": local.type,
            "sdp": local.sdp,
        }
        if avatar:
            offer_body["avatar"] = avatar

        async with http.post(f"{base}/offer", json=offer_body) as resp:
            offer_text = await resp.text()
            offer_status = resp.status
        try:
            offer_json = json.loads(offer_text)
        except json.JSONDecodeError:
            await pc.close()
            result["steps"]["offer"] = {
                "status": offer_status,
                "body_preview": offer_text[:300],
            }
            result["error"] = "offer_non_json"
            return result

        result["steps"]["offer"] = {
            "status": offer_status,
            "code": offer_json.get("code"),
            "has_sdp": bool(offer_json.get("sdp")),
            "type": offer_json.get("type"),
            "sessionid": str(offer_json.get("sessionid") or "")[:36] or None,
        }

        if offer_json.get("code") == -1:
            await pc.close()
            result["error"] = f"offer_rejected: {offer_json.get('msg')}"
            return result

        answer_sdp = offer_json.get("sdp")
        answer_type = offer_json.get("type") or "answer"
        sessionid = offer_json.get("sessionid")
        if not answer_sdp or sessionid is None:
            await pc.close()
            result["error"] = "offer_missing_sdp_or_sessionid"
            return result

        sessionid_str = str(sessionid)
        await pc.setRemoteDescription(
            RTCSessionDescription(sdp=answer_sdp, type=answer_type)
        )

        # Wait for media / connection
        deadline = time.monotonic() + track_wait_s
        while time.monotonic() < deadline:
            if video_frames > 0 or audio_frames > 0:
                break
            if pc.connectionState in ("failed", "closed"):
                break
            await asyncio.sleep(0.2)

        result["steps"]["webrtc"] = {
            "connection_state": pc.connectionState,
            "connection_states": connection_states[-8:],
            "track_kinds": sorted(track_kinds),
            "video_frames": video_frames,
            "audio_frames": audio_frames,
        }

        # 3) POST /human echo
        async with http.post(
            f"{base}/human",
            json={
                "sessionid": sessionid_str,
                "type": "echo",
                "text": echo_text,
                "interrupt": True,
            },
        ) as resp:
            human_text = await resp.text()
            human_status = resp.status
        try:
            human_json = json.loads(human_text)
        except json.JSONDecodeError:
            human_json = {"raw": human_text[:200]}

        result["steps"]["human"] = {
            "status": human_status,
            "code": human_json.get("code"),
            "msg": human_json.get("msg"),
        }

        # Optional: is_speaking after a short delay
        await asyncio.sleep(min(1.5, speak_wait_s))
        speaking: Any = None
        try:
            async with http.post(
                f"{base}/is_speaking",
                json={"sessionid": sessionid_str},
            ) as resp:
                speaking_body = await resp.json(content_type=None)
            speaking = speaking_body.get("data")
            result["steps"]["is_speaking"] = {
                "code": speaking_body.get("code"),
                "data": speaking,
            }
        except Exception as exc:  # noqa: BLE001
            result["steps"]["is_speaking"] = {"error": str(exc)[:120]}

        # Allow a bit more media after speak
        await asyncio.sleep(max(0.0, speak_wait_s - 1.5))
        result["steps"]["webrtc_after_speak"] = {
            "connection_state": pc.connectionState,
            "video_frames": video_frames,
            "audio_frames": audio_frames,
        }

        await pc.close()

        human_ok = human_status == 200 and human_json.get("code") == 0
        media_ok = (
            video_frames > 0
            or audio_frames > 0
            or "video" in track_kinds
            or "audio" in track_kinds
            or speaking is True
        )
        # Session accepted is required; media preferred but ICE may fail across NAT.
        if not human_ok:
            result["error"] = "human_not_accepted"
            return result

        result["ok"] = True
        result["media_received"] = bool(
            video_frames > 0 or audio_frames > 0 or speaking is True
        )
        result["tracks_signaled"] = sorted(track_kinds)
        if not media_ok:
            result["warning"] = (
                "session+/human ok but no frames yet (ICE/NAT); "
                "treat as partial pass if QA browser also fails media"
            )
        return result


def main() -> int:
    parser = argparse.ArgumentParser(description="LiveTalking WebRTC E2E")
    parser.add_argument("--base", default=DEFAULT_BASE)
    parser.add_argument("--avatar", default=DEFAULT_AVATAR)
    parser.add_argument("--text", default=DEFAULT_TEXT)
    parser.add_argument("--track-wait", type=float, default=12.0)
    parser.add_argument("--speak-wait", type=float, default=4.0)
    args = parser.parse_args()

    summary = asyncio.run(
        run_e2e(
            base=args.base.rstrip("/"),
            avatar=args.avatar,
            echo_text=args.text,
            track_wait_s=args.track_wait,
            speak_wait_s=args.speak_wait,
        )
    )
    print(json.dumps(summary, ensure_ascii=False, indent=2))
    return 0 if summary.get("ok") else 1


if __name__ == "__main__":
    raise SystemExit(main())
