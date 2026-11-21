"""Durable oral peer matching: DB queue → paired room → messages + heartbeat.

LiveKit tokens are minted when LIVEKIT_* is configured (agent_name=None).
"""

from __future__ import annotations

import asyncio
import time
import uuid

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field
from sqlalchemy import delete, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.deps import get_current_user
from app.models import OralMatchQueue, OralPeerMessage, OralPeerReport, OralPeerRoom, User
from app.services.livekit_tokens import create_room_token, livekit_configured

router = APIRouter(prefix="/oral-match", tags=["oral-match"])

_PAIR_LOCK = asyncio.Lock()
_QUEUE_TTL_SEC = 90
_ROOM_TTL_SEC = 45 * 60
_HEARTBEAT_ONLINE_SEC = 45


def _display_name(user: User) -> str:
    raw = (user.display_name or user.email or f"learner-{user.id}").strip()
    return raw[:32] or f"learner-{user.id}"


def _name_for(room: OralPeerRoom, user_id: int) -> str:
    if user_id == room.user_a:
        return room.name_a
    if user_id == room.user_b:
        return room.name_b
    return f"learner-{user_id}"


def _peer_of(room: OralPeerRoom, me: int) -> tuple[int, str]:
    if me == room.user_a:
        return room.user_b, room.name_b
    return room.user_a, room.name_a


def _peer_heartbeat(room: OralPeerRoom, me: int) -> float:
    return room.heartbeat_b if me == room.user_a else room.heartbeat_a


async def _purge(db: AsyncSession, now: float | None = None) -> None:
    ts = now or time.time()
    await db.execute(
        delete(OralMatchQueue).where(OralMatchQueue.heartbeat_at < ts - _QUEUE_TTL_SEC)
    )
    stale = (
        await db.execute(
            select(OralPeerRoom).where(
                OralPeerRoom.closed_at.is_(None),
                OralPeerRoom.created_at < ts - _ROOM_TTL_SEC,
            )
        )
    ).scalars().all()
    for room in stale:
        room.closed_at = ts
        room.left_by = None
    await db.flush()


async def _active_room_for(db: AsyncSession, user_id: int) -> OralPeerRoom | None:
    row = (
        await db.execute(
            select(OralPeerRoom)
            .where(
                OralPeerRoom.closed_at.is_(None),
                (OralPeerRoom.user_a == user_id) | (OralPeerRoom.user_b == user_id),
            )
            .order_by(OralPeerRoom.created_at.desc())
            .limit(1)
        )
    ).scalar_one_or_none()
    return row


def _livekit_payload(room: OralPeerRoom, me: int) -> dict | None:
    if not livekit_configured():
        return None
    try:
        return create_room_token(
            identity=f"user-{me}",
            room_name=f"oral-peer-{room.id}",
            name=_name_for(room, me),
            agent_name=None,
            ttl_seconds=3600,
            can_publish=True,
            can_subscribe=True,
        )
    except RuntimeError:
        return None


def _room_payload(room: OralPeerRoom, me: int, *, now: float | None = None) -> dict:
    ts = now or time.time()
    peer_id, peer_name = _peer_of(room, me)
    peer_hb = _peer_heartbeat(room, me)
    peer_online = (ts - peer_hb) <= _HEARTBEAT_ONLINE_SEC
    status_value = "matched"
    if room.closed_at is not None:
        status_value = "peer_left"
    return {
        "status": status_value,
        "room_id": room.id,
        "peer": {"user_id": peer_id, "display_name": peer_name},
        "peer_online": peer_online and room.closed_at is None,
        "voice_ready": livekit_configured(),
        "livekit": None if room.closed_at is not None else _livekit_payload(room, me),
    }


class EnqueueOut(BaseModel):
    status: str
    room_id: str | None = None
    peer: dict | None = None
    livekit: dict | None = None
    queue_position: int | None = None
    peer_online: bool | None = None
    voice_ready: bool | None = None


class MessageIn(BaseModel):
    text: str = Field(min_length=1, max_length=2000)


class MessageOut(BaseModel):
    id: str
    sender_user_id: int
    sender_name: str
    text: str
    created_at: float
    mine: bool
    kind: str = "user"


class ReportIn(BaseModel):
    reason: str = Field(min_length=2, max_length=500)


@router.post("/enqueue", response_model=EnqueueOut)
async def enqueue_match(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> EnqueueOut:
    now = time.time()
    name = _display_name(user)
    async with _PAIR_LOCK:
        await _purge(db, now)
        existing = await _active_room_for(db, user.id)
        if existing is not None:
            if user.id == existing.user_a:
                existing.heartbeat_a = now
            else:
                existing.heartbeat_b = now
            await db.commit()
            return EnqueueOut(**_room_payload(existing, user.id, now=now))

        waiting = (
            await db.execute(
                select(OralMatchQueue)
                .where(OralMatchQueue.user_id != user.id)
                .order_by(OralMatchQueue.enqueued_at.asc())
                .limit(1)
            )
        ).scalar_one_or_none()

        mine = await db.get(OralMatchQueue, user.id)
        if waiting is None:
            if mine is None:
                db.add(
                    OralMatchQueue(
                        user_id=user.id,
                        display_name=name,
                        enqueued_at=now,
                        heartbeat_at=now,
                    )
                )
            else:
                mine.display_name = name
                mine.heartbeat_at = now
            await db.commit()
            position = (
                await db.execute(select(OralMatchQueue).order_by(OralMatchQueue.enqueued_at.asc()))
            ).scalars().all()
            idx = next(
                (i for i, row in enumerate(position) if row.user_id == user.id),
                0,
            )
            return EnqueueOut(status="waiting", queue_position=idx + 1)

        # Pair with oldest waiter.
        partner = waiting
        room_id = uuid.uuid4().hex[:12]
        room = OralPeerRoom(
            id=room_id,
            user_a=partner.user_id,
            name_a=partner.display_name,
            user_b=user.id,
            name_b=name,
            created_at=now,
            heartbeat_a=now,
            heartbeat_b=now,
        )
        db.add(room)
        await db.execute(delete(OralMatchQueue).where(OralMatchQueue.user_id == partner.user_id))
        if mine is not None:
            await db.delete(mine)
        db.add(
            OralPeerMessage(
                id=uuid.uuid4().hex[:10],
                room_id=room_id,
                sender_user_id=0,
                sender_name="system",
                text="Matched. You can talk live and also hold-to-talk for AI rewrite.",
                created_at=now,
                kind="system",
            )
        )
        await db.commit()
        await db.refresh(room)
        return EnqueueOut(**_room_payload(room, user.id, now=now))


@router.get("/status", response_model=EnqueueOut)
async def match_status(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> EnqueueOut:
    now = time.time()
    await _purge(db, now)
    room = await _active_room_for(db, user.id)
    if room is not None:
        if user.id == room.user_a:
            room.heartbeat_a = now
        else:
            room.heartbeat_b = now
        await db.commit()
        return EnqueueOut(**_room_payload(room, user.id, now=now))

    # Closed room still visible briefly so client can show "peer left".
    closed = (
        await db.execute(
            select(OralPeerRoom)
            .where(
                OralPeerRoom.closed_at.is_not(None),
                (OralPeerRoom.user_a == user.id) | (OralPeerRoom.user_b == user.id),
                OralPeerRoom.closed_at >= now - 120,
            )
            .order_by(OralPeerRoom.closed_at.desc())
            .limit(1)
        )
    ).scalar_one_or_none()
    if closed is not None:
        payload = _room_payload(closed, user.id, now=now)
        payload["status"] = "peer_left"
        payload["peer_online"] = False
        payload["livekit"] = None
        return EnqueueOut(**payload)

    mine = await db.get(OralMatchQueue, user.id)
    if mine is not None:
        mine.heartbeat_at = now
        await db.commit()
        rows = (
            await db.execute(select(OralMatchQueue).order_by(OralMatchQueue.enqueued_at.asc()))
        ).scalars().all()
        idx = next((i for i, row in enumerate(rows) if row.user_id == user.id), 0)
        return EnqueueOut(status="waiting", queue_position=idx + 1)
    return EnqueueOut(status="idle")


@router.post("/heartbeat", response_model=EnqueueOut)
async def heartbeat(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> EnqueueOut:
    return await match_status(user=user, db=db)


@router.post("/leave")
async def leave_match(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict[str, str]:
    now = time.time()
    await db.execute(delete(OralMatchQueue).where(OralMatchQueue.user_id == user.id))
    room = await _active_room_for(db, user.id)
    if room is not None:
        room.closed_at = now
        room.left_by = user.id
        peer_id, _ = _peer_of(room, user.id)
        db.add(
            OralPeerMessage(
                id=uuid.uuid4().hex[:10],
                room_id=room.id,
                sender_user_id=0,
                sender_name="system",
                text=f"{_name_for(room, user.id)} left the practice.",
                created_at=now,
                kind="system",
            )
        )
        # Touch peer side so status poll notices quickly.
        if peer_id == room.user_a:
            room.heartbeat_a = room.heartbeat_a
        else:
            room.heartbeat_b = room.heartbeat_b
    await db.commit()
    return {"status": "left"}


@router.post("/rooms/{room_id}/messages", response_model=MessageOut)
async def post_message(
    room_id: str,
    body: MessageIn,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> MessageOut:
    text = body.text.strip()
    if not text:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, "Empty message.")
    room = await db.get(OralPeerRoom, room_id)
    if room is None or user.id not in {room.user_a, room.user_b}:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Room not found.")
    if room.closed_at is not None:
        raise HTTPException(status.HTTP_409_CONFLICT, "Room already closed.")
    now = time.time()
    if user.id == room.user_a:
        room.heartbeat_a = now
    else:
        room.heartbeat_b = now
    msg = OralPeerMessage(
        id=uuid.uuid4().hex[:10],
        room_id=room.id,
        sender_user_id=user.id,
        sender_name=_name_for(room, user.id),
        text=text[:2000],
        created_at=now,
        kind="user",
    )
    db.add(msg)
    # Cap retention per room.
    rows = (
        await db.execute(
            select(OralPeerMessage)
            .where(OralPeerMessage.room_id == room.id)
            .order_by(OralPeerMessage.created_at.desc())
        )
    ).scalars().all()
    for old in rows[199:]:
        await db.delete(old)
    await db.commit()
    return MessageOut(
        id=msg.id,
        sender_user_id=msg.sender_user_id,
        sender_name=msg.sender_name,
        text=msg.text,
        created_at=msg.created_at,
        mine=True,
        kind=msg.kind,
    )


@router.get("/rooms/{room_id}/messages")
async def list_messages(
    room_id: str,
    after_id: str | None = None,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    room = await db.get(OralPeerRoom, room_id)
    if room is None or user.id not in {room.user_a, room.user_b}:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Room not found.")
    rows = (
        await db.execute(
            select(OralPeerMessage)
            .where(OralPeerMessage.room_id == room_id)
            .order_by(OralPeerMessage.created_at.asc())
        )
    ).scalars().all()
    if after_id:
        idx = next((i for i, m in enumerate(rows) if m.id == after_id), -1)
        rows = rows[idx + 1 :] if idx >= 0 else rows
    return {
        "messages": [
            MessageOut(
                id=m.id,
                sender_user_id=m.sender_user_id,
                sender_name=m.sender_name,
                text=m.text,
                created_at=m.created_at,
                mine=m.sender_user_id == user.id,
                kind=m.kind or "user",
            ).model_dump()
            for m in rows
        ],
        "room_closed": room.closed_at is not None,
        "peer_online": (
            room.closed_at is None
            and (time.time() - _peer_heartbeat(room, user.id)) <= _HEARTBEAT_ONLINE_SEC
        ),
    }


@router.post("/rooms/{room_id}/report")
async def report_peer(
    room_id: str,
    body: ReportIn,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict[str, str]:
    room = await db.get(OralPeerRoom, room_id)
    if room is None or user.id not in {room.user_a, room.user_b}:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Room not found.")
    peer_id, _ = _peer_of(room, user.id)
    db.add(
        OralPeerReport(
            room_id=room.id,
            reporter_user_id=user.id,
            peer_user_id=peer_id,
            reason=body.reason.strip()[:500],
        )
    )
    await db.commit()
    return {"status": "reported"}
