"""Ephemeral oral peer matching: queue → paired room → text messages.

LiveKit tokens are optional when the server has LIVEKIT_* configured.
"""

from __future__ import annotations

import threading
import time
import uuid
from dataclasses import dataclass, field

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field

from app.deps import get_current_user
from app.models import User
from app.services.livekit_tokens import create_room_token, livekit_configured

router = APIRouter(prefix="/oral-match", tags=["oral-match"])

_LOCK = threading.Lock()
_QUEUE_TTL_SEC = 90
_ROOM_TTL_SEC = 30 * 60


@dataclass
class _QueueEntry:
    user_id: int
    display_name: str
    enqueued_at: float


@dataclass
class _RoomMessage:
    id: str
    sender_user_id: int
    sender_name: str
    text: str
    created_at: float


@dataclass
class _Room:
    id: str
    user_a: int
    name_a: str
    user_b: int
    name_b: str
    created_at: float
    messages: list[_RoomMessage] = field(default_factory=list)


_queue: list[_QueueEntry] = []
_rooms: dict[str, _Room] = {}
_user_room: dict[int, str] = {}


def _purge_locked(now: float | None = None) -> None:
    ts = now or time.time()
    alive: list[_QueueEntry] = []
    for item in _queue:
        if ts - item.enqueued_at <= _QUEUE_TTL_SEC:
            alive.append(item)
    _queue[:] = alive
    stale = [
        rid
        for rid, room in _rooms.items()
        if ts - room.created_at > _ROOM_TTL_SEC
    ]
    for rid in stale:
        room = _rooms.pop(rid, None)
        if room is None:
            continue
        _user_room.pop(room.user_a, None)
        _user_room.pop(room.user_b, None)


def _display_name(user: User) -> str:
    raw = (user.display_name or user.email or f"learner-{user.id}").strip()
    return raw[:32] or f"learner-{user.id}"


def _room_payload(room: _Room, me: int) -> dict:
    peer_id = room.user_b if me == room.user_a else room.user_a
    peer_name = room.name_b if me == room.user_a else room.name_a
    livekit: dict | None = None
    if livekit_configured():
        try:
            livekit = create_room_token(
                identity=f"user-{me}",
                room_name=f"oral-peer-{room.id}",
                name=_display_name_for_id(me, room),
                agent_name=None,
            )
        except RuntimeError:
            livekit = None
    return {
        "status": "matched",
        "room_id": room.id,
        "peer": {"user_id": peer_id, "display_name": peer_name},
        "livekit": livekit,
    }


def _display_name_for_id(user_id: int, room: _Room) -> str:
    if user_id == room.user_a:
        return room.name_a
    if user_id == room.user_b:
        return room.name_b
    return f"learner-{user_id}"


class EnqueueOut(BaseModel):
    status: str
    room_id: str | None = None
    peer: dict | None = None
    livekit: dict | None = None
    queue_position: int | None = None


class MessageIn(BaseModel):
    text: str = Field(min_length=1, max_length=2000)


class MessageOut(BaseModel):
    id: str
    sender_user_id: int
    sender_name: str
    text: str
    created_at: float
    mine: bool


@router.post("/enqueue", response_model=EnqueueOut)
async def enqueue_match(user: User = Depends(get_current_user)) -> EnqueueOut:
    now = time.time()
    name = _display_name(user)
    with _LOCK:
        _purge_locked(now)
        existing_room_id = _user_room.get(user.id)
        if existing_room_id and existing_room_id in _rooms:
            return EnqueueOut(**_room_payload(_rooms[existing_room_id], user.id))

        # Already waiting?
        for idx, item in enumerate(_queue):
            if item.user_id == user.id:
                item.enqueued_at = now
                item.display_name = name
                return EnqueueOut(status="waiting", queue_position=idx + 1)

        # Pair with the oldest waiter who is not me.
        partner: _QueueEntry | None = None
        remain: list[_QueueEntry] = []
        for item in _queue:
            if partner is None and item.user_id != user.id:
                partner = item
                continue
            remain.append(item)
        _queue[:] = remain

        if partner is not None:
            room_id = uuid.uuid4().hex[:12]
            room = _Room(
                id=room_id,
                user_a=partner.user_id,
                name_a=partner.display_name,
                user_b=user.id,
                name_b=name,
                created_at=now,
            )
            _rooms[room_id] = room
            _user_room[partner.user_id] = room_id
            _user_room[user.id] = room_id
            return EnqueueOut(**_room_payload(room, user.id))

        _queue.append(
            _QueueEntry(user_id=user.id, display_name=name, enqueued_at=now)
        )
        return EnqueueOut(status="waiting", queue_position=len(_queue))


@router.get("/status", response_model=EnqueueOut)
async def match_status(user: User = Depends(get_current_user)) -> EnqueueOut:
    now = time.time()
    with _LOCK:
        _purge_locked(now)
        room_id = _user_room.get(user.id)
        if room_id and room_id in _rooms:
            return EnqueueOut(**_room_payload(_rooms[room_id], user.id))
        for idx, item in enumerate(_queue):
            if item.user_id == user.id:
                return EnqueueOut(status="waiting", queue_position=idx + 1)
        return EnqueueOut(status="idle")


@router.post("/leave")
async def leave_match(user: User = Depends(get_current_user)) -> dict[str, str]:
    with _LOCK:
        _purge_locked()
        _queue[:] = [item for item in _queue if item.user_id != user.id]
        room_id = _user_room.pop(user.id, None)
        if room_id and room_id in _rooms:
            room = _rooms.pop(room_id)
            _user_room.pop(room.user_a, None)
            _user_room.pop(room.user_b, None)
    return {"status": "left"}


@router.post("/rooms/{room_id}/messages", response_model=MessageOut)
async def post_message(
    room_id: str,
    body: MessageIn,
    user: User = Depends(get_current_user),
) -> MessageOut:
    text = body.text.strip()
    if not text:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, "Empty message.")
    with _LOCK:
        _purge_locked()
        room = _rooms.get(room_id)
        if room is None or user.id not in {room.user_a, room.user_b}:
            raise HTTPException(status.HTTP_404_NOT_FOUND, "Room not found.")
        msg = _RoomMessage(
            id=uuid.uuid4().hex[:10],
            sender_user_id=user.id,
            sender_name=_display_name_for_id(user.id, room),
            text=text[:2000],
            created_at=time.time(),
        )
        room.messages.append(msg)
        if len(room.messages) > 200:
            room.messages = room.messages[-200:]
        return MessageOut(
            id=msg.id,
            sender_user_id=msg.sender_user_id,
            sender_name=msg.sender_name,
            text=msg.text,
            created_at=msg.created_at,
            mine=True,
        )


@router.get("/rooms/{room_id}/messages")
async def list_messages(
    room_id: str,
    after_id: str | None = None,
    user: User = Depends(get_current_user),
) -> dict:
    with _LOCK:
        _purge_locked()
        room = _rooms.get(room_id)
        if room is None or user.id not in {room.user_a, room.user_b}:
            raise HTTPException(status.HTTP_404_NOT_FOUND, "Room not found.")
        rows = list(room.messages)
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
            ).model_dump()
            for m in rows
        ]
    }
