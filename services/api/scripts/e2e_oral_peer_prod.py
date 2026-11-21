#!/usr/bin/env python3
"""Production peer-oral closed-loop probe (run on ECS against localhost:5200).

Creates two throwaway users, matches them, checks LiveKit token + messages +
heartbeat + learning peer_oral task + leave/rematch.
"""

from __future__ import annotations

import asyncio
import sys
import uuid

import httpx

from app.database import SessionLocal
from app.models import User
from app.security import create_access_token, hash_password

BASE = "http://127.0.0.1:5200"


async def _make_user(tag: str) -> tuple[str, str]:
    suffix = uuid.uuid4().hex[:10]
    email = f"peer_e2e_{tag}_{suffix}@example.com"
    password = f"PeerE2e_{suffix}!"
    async with SessionLocal() as db:
        user = User(
            email=email,
            hashed_password=hash_password(password),
            display_name=f"PeerE2E {tag}",
        )
        db.add(user)
        await db.commit()
        await db.refresh(user)
        token = create_access_token(user.email)
        return token, email


def _auth(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


async def main() -> int:
    token_a, email_a = await _make_user("a")
    token_b, email_b = await _make_user("b")
    print("users", email_a, email_b)

    async with httpx.AsyncClient(base_url=BASE, timeout=30.0) as api:
        health = await api.get("/api/health")
        health.raise_for_status()
        assert health.json().get("status") == "ok"
        assert health.json().get("livekit"), "LiveKit URL missing in health"

        first = await api.post("/api/oral-match/enqueue", headers=_auth(token_a))
        assert first.status_code == 200, first.text
        assert first.json()["status"] == "waiting", first.text

        second = await api.post("/api/oral-match/enqueue", headers=_auth(token_b))
        assert second.status_code == 200, second.text
        body = second.json()
        assert body["status"] == "matched", body
        room_id = body["room_id"]
        assert room_id
        assert body.get("peer_online") is True
        livekit = body.get("livekit")
        assert livekit and livekit.get("token") and livekit.get("url"), body
        assert str(livekit.get("room", "")).startswith("oral-peer-"), livekit

        beat = await api.post("/api/oral-match/heartbeat", headers=_auth(token_a))
        assert beat.status_code == 200, beat.text
        assert beat.json()["status"] == "matched"

        sent = await api.post(
            f"/api/oral-match/rooms/{room_id}/messages",
            headers=_auth(token_b),
            json={"text": "I just popped to the supermarket."},
        )
        assert sent.status_code == 200, sent.text

        inbox = await api.get(
            f"/api/oral-match/rooms/{room_id}/messages",
            headers=_auth(token_a),
        )
        assert inbox.status_code == 200, inbox.text
        msgs = inbox.json()["messages"]
        assert any((m.get("text") or "").startswith("I just popped") for m in msgs)
        assert inbox.json().get("room_closed") is False

        tasks = await api.get("/api/learning/tasks")
        assert tasks.status_code == 200, tasks.text
        assert any(t.get("id") == "peer_oral" for t in tasks.json()), tasks.text

        session = await api.post(
            "/api/learning/sessions",
            headers=_auth(token_a),
            json={
                "task_id": "peer_oral",
                "course_title": "真人口语对练",
                "current_english": "I just popped to the supermarket.",
            },
        )
        assert session.status_code == 200, session.text
        sid = session.json()["id"]
        turn = await api.post(
            f"/api/learning/sessions/{sid}/turns",
            headers=_auth(token_a),
            json={
                "role": "user",
                "text": "I just popped to the supermarket.",
                "confirmed": True,
            },
        )
        assert turn.status_code == 200, turn.text
        review = await api.post(
            "/api/learning/reviews",
            headers=_auth(token_a),
            json={
                "expression": "I just popped to the supermarket.",
                "source_quote": "我刚去了一趟超市。",
            },
        )
        assert review.status_code == 200, review.text
        assert review.json().get("id")

        leave = await api.post("/api/oral-match/leave", headers=_auth(token_b))
        assert leave.status_code == 200, leave.text
        left = await api.get("/api/oral-match/status", headers=_auth(token_a))
        assert left.status_code == 200, left.text
        assert left.json()["status"] == "peer_left", left.text

        rematch = await api.post("/api/oral-match/enqueue", headers=_auth(token_a))
        assert rematch.status_code == 200, rematch.text
        assert rematch.json()["status"] in {"waiting", "matched"}, rematch.text

        # Cleanup leave so queue does not pollute later probes.
        await api.post("/api/oral-match/leave", headers=_auth(token_a))

    print("OK peer oral closed loop")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(asyncio.run(main()))
    except Exception as exc:  # noqa: BLE001
        print("FAIL", type(exc).__name__, exc, file=sys.stderr)
        raise SystemExit(1) from exc
