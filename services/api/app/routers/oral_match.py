"""Durable oral peer matching: DB queue → invite lobby → paired room.

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
from app.models import (
    OralInviteLobby,
    OralMatchQueue,
    OralPeerMessage,
    OralPeerReport,
    OralPeerRoom,
    User,
)
from app.services.livekit_tokens import create_room_token, livekit_configured

router = APIRouter(prefix="/oral-match", tags=["oral-match"])

_PAIR_LOCK = asyncio.Lock()
_QUEUE_TTL_SEC = 90
_INVITE_TTL_SEC = 10 * 60
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


def _norm_lang(value: str) -> str:
    return (value or "").strip().lower()[:16]


def _norm_topic(value: str) -> str:
    return (value or "").strip()[:64]


def _norm_kind(value: str) -> str:
    kind = (value or "").strip().lower()[:16]
    return kind if kind in {"video", "article"} else ""


def _content_fields(source: object) -> dict[str, str]:
    return {
        "topic": _norm_topic(getattr(source, "topic", "") or ""),
        "content_kind": _norm_kind(getattr(source, "content_kind", "") or ""),
        "content_id": (getattr(source, "content_id", "") or "").strip()[:128],
        "content_title": (getattr(source, "content_title", "") or "").strip()[:200],
        "content_route": (getattr(source, "content_route", "") or "").strip()[:512],
    }


async def _purge(db: AsyncSession, now: float | None = None) -> None:
    ts = now or time.time()
    await db.execute(
        delete(OralMatchQueue).where(OralMatchQueue.heartbeat_at < ts - _QUEUE_TTL_SEC)
    )
    await db.execute(
        delete(OralInviteLobby).where(
            OralInviteLobby.closed_at.is_(None),
            OralInviteLobby.heartbeat_at < ts - _INVITE_TTL_SEC,
        )
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


async def _active_invite_for(db: AsyncSession, user_id: int) -> OralInviteLobby | None:
    return (
        await db.execute(
            select(OralInviteLobby)
            .where(
                OralInviteLobby.host_user_id == user_id,
                OralInviteLobby.closed_at.is_(None),
            )
            .order_by(OralInviteLobby.created_at.desc())
            .limit(1)
        )
    ).scalar_one_or_none()


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
        "topic": room.topic or None,
        "content_kind": room.content_kind or None,
        "content_id": room.content_id or None,
        "content_title": room.content_title or None,
        "content_route": room.content_route or None,
    }


def _invite_payload(invite: OralInviteLobby) -> dict:
    return {
        "status": "waiting_invite",
        "invite_id": invite.id,
        "room_id": None,
        "host": {
            "user_id": invite.host_user_id,
            "display_name": invite.host_name,
        },
        "topic": invite.topic or None,
        "content_kind": invite.content_kind or None,
        "content_id": invite.content_id or None,
        "content_title": invite.content_title or None,
        "content_route": invite.content_route or None,
        "created_at": invite.created_at,
    }


class EnqueueIn(BaseModel):
    mode: str = Field(default="peer_oral", max_length=32)
    native_lang: str = Field(default="", max_length=16)
    target_lang: str = Field(default="", max_length=16)
    topic: str = Field(default="", max_length=64)
    cefr: str = Field(default="", max_length=8)
    content_kind: str = Field(default="", max_length=16)
    content_id: str = Field(default="", max_length=128)
    content_title: str = Field(default="", max_length=200)
    content_route: str = Field(default="", max_length=512)


class EnqueueOut(BaseModel):
    status: str
    room_id: str | None = None
    invite_id: str | None = None
    peer: dict | None = None
    host: dict | None = None
    livekit: dict | None = None
    queue_position: int | None = None
    peer_online: bool | None = None
    voice_ready: bool | None = None
    mode: str | None = None
    topic: str | None = None
    content_kind: str | None = None
    content_id: str | None = None
    content_title: str | None = None
    content_route: str | None = None


class InviteCreateIn(BaseModel):
    topic: str = Field(default="", max_length=64)
    content_kind: str = Field(default="", max_length=16)
    content_id: str = Field(default="", max_length=128)
    content_title: str = Field(default="", max_length=200)
    content_route: str = Field(default="", max_length=512)


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


def _compatible_partner(mine: dict[str, str], other: OralMatchQueue) -> bool:
    mode = (mine.get("mode") or "peer_oral").strip() or "peer_oral"
    other_mode = (getattr(other, "mode", None) or "peer_oral").strip() or "peer_oral"
    if mode != other_mode:
        return False
    if mode != "language_exchange":
        return True
    my_native = _norm_lang(mine.get("native_lang", ""))
    my_target = _norm_lang(mine.get("target_lang", ""))
    their_native = _norm_lang(getattr(other, "native_lang", "") or "")
    their_target = _norm_lang(getattr(other, "target_lang", "") or "")
    if not my_native or not my_target or not their_native or not their_target:
        return False
    return my_native == their_target and my_target == their_native


def _partner_score(mine: dict[str, str], other: OralMatchQueue) -> int:
    score = 0
    my_topic = mine.get("topic") or ""
    their_topic = (getattr(other, "topic", "") or "").strip()
    if my_topic and their_topic and my_topic == their_topic:
        score += 10
    my_cid = mine.get("content_id") or ""
    their_cid = (getattr(other, "content_id", "") or "").strip()
    if my_cid and their_cid and my_cid == their_cid:
        score += 20
    my_kind = mine.get("content_kind") or ""
    their_kind = _norm_kind(getattr(other, "content_kind", "") or "")
    if my_kind and their_kind and my_kind == their_kind:
        score += 3
    return score


def _pick_content(left: dict[str, str], right: dict[str, str]) -> dict[str, str]:
    if left.get("content_id"):
        return left
    if right.get("content_id"):
        return right
    if left.get("topic"):
        return left
    return right


async def _create_paired_room(
    db: AsyncSession,
    *,
    user_a: int,
    name_a: str,
    user_b: int,
    name_b: str,
    content: dict[str, str],
    mode: str,
    now: float,
) -> OralPeerRoom:
    room_id = uuid.uuid4().hex[:12]
    room = OralPeerRoom(
        id=room_id,
        user_a=user_a,
        name_a=name_a,
        user_b=user_b,
        name_b=name_b,
        created_at=now,
        heartbeat_a=now,
        heartbeat_b=now,
        topic=content.get("topic", ""),
        content_kind=content.get("content_kind", ""),
        content_id=content.get("content_id", ""),
        content_title=content.get("content_title", ""),
        content_route=content.get("content_route", ""),
    )
    db.add(room)
    topic = content.get("topic") or ""
    title = content.get("content_title") or ""
    kind = content.get("content_kind") or ""
    bits = ["Matched."]
    if topic:
        bits.append(f"Topic: {topic}.")
    if title:
        label = "video" if kind == "video" else ("article" if kind == "article" else "material")
        bits.append(f"Shared {label}: {title}.")
    bits.append("Talk about it live, or hold-to-talk for AI rewrite then send.")
    if mode == "language_exchange":
        bits = [
            f"Language exchange matched{(' · ' + topic) if topic else ''}.",
            "Take turns in each language.",
        ]
        if title:
            bits.append(f"Shared material: {title}.")
    db.add(
        OralPeerMessage(
            id=uuid.uuid4().hex[:10],
            room_id=room_id,
            sender_user_id=0,
            sender_name="system",
            text=" ".join(bits),
            created_at=now,
            kind="system",
        )
    )
    return room


@router.post("/enqueue", response_model=EnqueueOut)
async def enqueue_match(
    payload: EnqueueIn = EnqueueIn(),
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> EnqueueOut:
    body = payload
    now = time.time()
    name = _display_name(user)
    mode = (body.mode or "peer_oral").strip() or "peer_oral"
    if mode not in {"peer_oral", "language_exchange"}:
        mode = "peer_oral"
    prefs = {
        "mode": mode,
        "native_lang": _norm_lang(body.native_lang),
        "target_lang": _norm_lang(body.target_lang),
        "topic": _norm_topic(body.topic),
        "cefr": (body.cefr or "").strip().upper()[:8],
        "content_kind": _norm_kind(body.content_kind),
        "content_id": (body.content_id or "").strip()[:128],
        "content_title": (body.content_title or "").strip()[:200],
        "content_route": (body.content_route or "").strip()[:512],
    }
    if mode == "language_exchange" and (
        not prefs["native_lang"] or not prefs["target_lang"]
    ):
        raise HTTPException(400, "语言交换需填写母语与目标语")
    async with _PAIR_LOCK:
        await _purge(db, now)
        existing = await _active_room_for(db, user.id)
        if existing is not None:
            if user.id == existing.user_a:
                existing.heartbeat_a = now
            else:
                existing.heartbeat_b = now
            await db.commit()
            out = EnqueueOut(**_room_payload(existing, user.id, now=now))
            out.mode = mode
            return out

        invite = await _active_invite_for(db, user.id)
        if invite is not None:
            invite.heartbeat_at = now
            await db.commit()
            return EnqueueOut(**_invite_payload(invite), mode=mode)

        candidates = (
            await db.execute(
                select(OralMatchQueue)
                .where(OralMatchQueue.user_id != user.id)
                .order_by(OralMatchQueue.enqueued_at.asc())
                .limit(40)
            )
        ).scalars().all()
        compatible = [row for row in candidates if _compatible_partner(prefs, row)]
        waiting = None
        if compatible:
            waiting = max(compatible, key=lambda row: _partner_score(prefs, row))

        mine = await db.get(OralMatchQueue, user.id)
        if waiting is None:
            if mine is None:
                db.add(
                    OralMatchQueue(
                        user_id=user.id,
                        display_name=name,
                        enqueued_at=now,
                        heartbeat_at=now,
                        mode=mode,
                        native_lang=prefs["native_lang"],
                        target_lang=prefs["target_lang"],
                        topic=prefs["topic"],
                        cefr=prefs["cefr"],
                        content_kind=prefs["content_kind"],
                        content_id=prefs["content_id"],
                        content_title=prefs["content_title"],
                        content_route=prefs["content_route"],
                    )
                )
            else:
                mine.display_name = name
                mine.heartbeat_at = now
                mine.mode = mode
                mine.native_lang = prefs["native_lang"]
                mine.target_lang = prefs["target_lang"]
                mine.topic = prefs["topic"]
                mine.cefr = prefs["cefr"]
                mine.content_kind = prefs["content_kind"]
                mine.content_id = prefs["content_id"]
                mine.content_title = prefs["content_title"]
                mine.content_route = prefs["content_route"]
            await db.commit()
            position = (
                await db.execute(
                    select(OralMatchQueue)
                    .where(OralMatchQueue.mode == mode)
                    .order_by(OralMatchQueue.enqueued_at.asc())
                )
            ).scalars().all()
            idx = next(
                (i for i, row in enumerate(position) if row.user_id == user.id),
                0,
            )
            return EnqueueOut(
                status="waiting",
                queue_position=idx + 1,
                mode=mode,
                topic=prefs["topic"] or None,
                content_kind=prefs["content_kind"] or None,
                content_id=prefs["content_id"] or None,
                content_title=prefs["content_title"] or None,
                content_route=prefs["content_route"] or None,
            )

        partner = waiting
        content = _pick_content(prefs, _content_fields(partner))
        room = await _create_paired_room(
            db,
            user_a=partner.user_id,
            name_a=partner.display_name,
            user_b=user.id,
            name_b=name,
            content=content,
            mode=mode,
            now=now,
        )
        await db.execute(
            delete(OralMatchQueue).where(OralMatchQueue.user_id == partner.user_id)
        )
        if mine is not None:
            await db.delete(mine)
        await db.commit()
        await db.refresh(room)
        out = EnqueueOut(**_room_payload(room, user.id, now=now))
        out.mode = mode
        return out


@router.post("/invites", response_model=EnqueueOut)
async def create_invite(
    payload: InviteCreateIn = InviteCreateIn(),
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> EnqueueOut:
    now = time.time()
    name = _display_name(user)
    content = {
        "topic": _norm_topic(payload.topic),
        "content_kind": _norm_kind(payload.content_kind),
        "content_id": (payload.content_id or "").strip()[:128],
        "content_title": (payload.content_title or "").strip()[:200],
        "content_route": (payload.content_route or "").strip()[:512],
    }
    async with _PAIR_LOCK:
        await _purge(db, now)
        existing = await _active_room_for(db, user.id)
        if existing is not None:
            raise HTTPException(409, "已在对练房间中，请先结束后再发邀请")
        invite = await _active_invite_for(db, user.id)
        if invite is None:
            invite = OralInviteLobby(
                id=uuid.uuid4().hex[:12],
                host_user_id=user.id,
                host_name=name,
                topic=content["topic"],
                content_kind=content["content_kind"],
                content_id=content["content_id"],
                content_title=content["content_title"],
                content_route=content["content_route"],
                created_at=now,
                heartbeat_at=now,
            )
            db.add(invite)
        else:
            invite.host_name = name
            invite.heartbeat_at = now
            invite.topic = content["topic"]
            invite.content_kind = content["content_kind"]
            invite.content_id = content["content_id"]
            invite.content_title = content["content_title"]
            invite.content_route = content["content_route"]
        await db.execute(delete(OralMatchQueue).where(OralMatchQueue.user_id == user.id))
        await db.commit()
        await db.refresh(invite)
        return EnqueueOut(**_invite_payload(invite))


@router.get("/invites")
async def list_invites(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    now = time.time()
    await _purge(db, now)
    rows = (
        await db.execute(
            select(OralInviteLobby)
            .where(
                OralInviteLobby.closed_at.is_(None),
                OralInviteLobby.host_user_id != user.id,
                OralInviteLobby.heartbeat_at >= now - _INVITE_TTL_SEC,
            )
            .order_by(OralInviteLobby.created_at.desc())
            .limit(40)
        )
    ).scalars().all()
    return {"invites": [_invite_payload(row) for row in rows]}


@router.post("/invites/{invite_id}/accept", response_model=EnqueueOut)
async def accept_invite(
    invite_id: str,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> EnqueueOut:
    now = time.time()
    name = _display_name(user)
    async with _PAIR_LOCK:
        await _purge(db, now)
        if await _active_room_for(db, user.id) is not None:
            raise HTTPException(409, "已在对练房间中")
        invite = await db.get(OralInviteLobby, invite_id)
        if invite is None or invite.closed_at is not None:
            raise HTTPException(404, "邀请不存在或已失效")
        if invite.host_user_id == user.id:
            raise HTTPException(400, "不能接受自己的邀请")
        if invite.heartbeat_at < now - _INVITE_TTL_SEC:
            invite.closed_at = now
            await db.commit()
            raise HTTPException(410, "邀请已过期")

        content = _content_fields(invite)
        room = await _create_paired_room(
            db,
            user_a=invite.host_user_id,
            name_a=invite.host_name,
            user_b=user.id,
            name_b=name,
            content=content,
            mode="peer_oral",
            now=now,
        )
        invite.closed_at = now
        await db.execute(
            delete(OralMatchQueue).where(
                OralMatchQueue.user_id.in_([invite.host_user_id, user.id])
            )
        )
        host_invite = await _active_invite_for(db, user.id)
        if host_invite is not None:
            host_invite.closed_at = now
        await db.commit()
        await db.refresh(room)
        return EnqueueOut(**_room_payload(room, user.id, now=now))


@router.post("/invites/{invite_id}/cancel")
async def cancel_invite(
    invite_id: str,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict[str, str]:
    now = time.time()
    invite = await db.get(OralInviteLobby, invite_id)
    if invite is None or invite.host_user_id != user.id:
        raise HTTPException(404, "邀请不存在")
    if invite.closed_at is None:
        invite.closed_at = now
        await db.commit()
    return {"status": "cancelled"}


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

    invite = await _active_invite_for(db, user.id)
    if invite is not None:
        invite.heartbeat_at = now
        await db.commit()
        return EnqueueOut(**_invite_payload(invite))

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
        return EnqueueOut(
            status="waiting",
            queue_position=idx + 1,
            topic=mine.topic or None,
            content_kind=mine.content_kind or None,
            content_id=mine.content_id or None,
            content_title=mine.content_title or None,
            content_route=mine.content_route or None,
        )
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
    invite = await _active_invite_for(db, user.id)
    if invite is not None:
        invite.closed_at = now
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
        "topic": room.topic or None,
        "content_kind": room.content_kind or None,
        "content_id": room.content_id or None,
        "content_title": room.content_title or None,
        "content_route": room.content_route or None,
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
