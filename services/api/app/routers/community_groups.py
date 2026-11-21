"""Formal study groups + weekly tasks (community P2)."""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Literal

from fastapi import APIRouter, Depends, HTTPException, Query, status
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.deps import get_current_user, get_current_user_optional
from app.models import (
    CommunityGroupTask,
    CommunityStudyGroup,
    CommunityStudyGroupMember,
    User,
)

router = APIRouter(prefix="/community/groups", tags=["community-groups"])

Visibility = Literal["public", "friends", "private"]


class GroupCreate(BaseModel):
    title: str = Field(min_length=1, max_length=120)
    description: str = Field(default="", max_length=2000)
    topic: str = Field(default="", max_length=64)
    cefr: str = Field(default="", max_length=8)
    visibility: Visibility = "public"


class GroupOut(BaseModel):
    id: int
    owner_id: int
    owner_name: str
    title: str
    description: str
    topic: str
    cefr: str
    visibility: str
    member_count: int
    status: str
    joined: bool = False
    created_at: datetime


class TaskCreate(BaseModel):
    title: str = Field(min_length=1, max_length=200)
    task_type: str = Field(default="shadowing", max_length=32)
    week_id: str | None = Field(default=None, max_length=16)
    material_pack_id: int | None = None
    link_url: str | None = Field(default=None, max_length=1024)


class TaskOut(BaseModel):
    id: int
    group_id: int
    week_id: str
    title: str
    task_type: str
    material_pack_id: int | None = None
    link_url: str | None = None
    created_by: int
    created_at: datetime


def _public_name(user: User | None) -> str:
    if user is None:
        return "学员"
    name = (user.display_name or "").strip()
    if name:
        return name[:40]
    return f"学员{user.id:04d}"


def _week_id(moment: datetime | None = None) -> str:
    moment = moment or datetime.now(timezone.utc)
    iso = moment.isocalendar()
    return f"{iso.year}-W{iso.week:02d}"


def _serialize_group(
    group: CommunityStudyGroup,
    *,
    owner: User | None,
    joined: bool,
) -> GroupOut:
    return GroupOut(
        id=group.id,
        owner_id=group.owner_id,
        owner_name=_public_name(owner),
        title=group.title or "",
        description=group.description or "",
        topic=group.topic or "",
        cefr=group.cefr or "",
        visibility=group.visibility or "public",
        member_count=int(group.member_count or 1),
        status=group.status or "open",
        joined=joined,
        created_at=group.created_at,
    )


@router.get("", response_model=list[GroupOut])
async def list_groups(
    mine: bool = False,
    limit: int = Query(default=40, ge=1, le=100),
    db: AsyncSession = Depends(get_db),
    user: User | None = Depends(get_current_user_optional),
) -> list[GroupOut]:
    if mine and user is None:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Not authenticated")
    stmt = (
        select(CommunityStudyGroup)
        .where(CommunityStudyGroup.status == "open")
        .order_by(CommunityStudyGroup.id.desc())
        .limit(limit)
    )
    if mine:
        assert user is not None
        member_ids = (
            await db.execute(
                select(CommunityStudyGroupMember.group_id).where(
                    CommunityStudyGroupMember.user_id == user.id
                )
            )
        ).scalars().all()
        if not member_ids:
            return []
        stmt = stmt.where(CommunityStudyGroup.id.in_(member_ids))
    else:
        stmt = stmt.where(CommunityStudyGroup.visibility == "public")
    groups = list((await db.execute(stmt)).scalars().all())
    if not groups:
        return []
    owners = {
        u.id: u
        for u in (
            await db.execute(select(User).where(User.id.in_({g.owner_id for g in groups})))
        ).scalars().all()
    }
    joined_ids: set[int] = set()
    if user is not None:
        joined_ids = set(
            (
                await db.execute(
                    select(CommunityStudyGroupMember.group_id).where(
                        CommunityStudyGroupMember.user_id == user.id,
                        CommunityStudyGroupMember.group_id.in_({g.id for g in groups}),
                    )
                )
            ).scalars().all()
        )
    return [
        _serialize_group(g, owner=owners.get(g.owner_id), joined=g.id in joined_ids)
        for g in groups
    ]


@router.post("", response_model=GroupOut, status_code=201)
async def create_group(
    payload: GroupCreate,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
) -> GroupOut:
    group = CommunityStudyGroup(
        owner_id=user.id,
        title=payload.title.strip(),
        description=(payload.description or "").strip(),
        topic=(payload.topic or "").strip()[:64],
        cefr=(payload.cefr or "").strip().upper()[:8],
        visibility=payload.visibility,
        member_count=1,
        status="open",
    )
    db.add(group)
    await db.flush()
    db.add(
        CommunityStudyGroupMember(
            group_id=group.id,
            user_id=user.id,
            role="owner",
        )
    )
    await db.commit()
    await db.refresh(group)
    return _serialize_group(group, owner=user, joined=True)


@router.post("/{group_id}/join", response_model=GroupOut)
async def join_group(
    group_id: int,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
) -> GroupOut:
    group = await db.get(CommunityStudyGroup, group_id)
    if group is None or group.status != "open":
        raise HTTPException(404, "小组不存在")
    if group.visibility != "public" and group.owner_id != user.id:
        raise HTTPException(403, "该小组不可加入")
    existing = await db.get(CommunityStudyGroupMember, {"group_id": group_id, "user_id": user.id})
    if existing is None:
        db.add(
            CommunityStudyGroupMember(
                group_id=group_id,
                user_id=user.id,
                role="member",
            )
        )
        group.member_count = int(group.member_count or 0) + 1
        await db.commit()
        await db.refresh(group)
    owner = await db.get(User, group.owner_id)
    return _serialize_group(group, owner=owner, joined=True)


@router.get("/{group_id}/tasks", response_model=list[TaskOut])
async def list_tasks(
    group_id: int,
    db: AsyncSession = Depends(get_db),
    user: User | None = Depends(get_current_user_optional),
) -> list[TaskOut]:
    group = await db.get(CommunityStudyGroup, group_id)
    if group is None:
        raise HTTPException(404, "小组不存在")
    if group.visibility != "public":
        if user is None:
            raise HTTPException(401, "Not authenticated")
        member = await db.get(
            CommunityStudyGroupMember, {"group_id": group_id, "user_id": user.id}
        )
        if member is None:
            raise HTTPException(403, "仅成员可查看任务")
    rows = (
        await db.execute(
            select(CommunityGroupTask)
            .where(CommunityGroupTask.group_id == group_id)
            .order_by(CommunityGroupTask.id.desc())
            .limit(40)
        )
    ).scalars().all()
    return [
        TaskOut(
            id=r.id,
            group_id=r.group_id,
            week_id=r.week_id,
            title=r.title,
            task_type=r.task_type,
            material_pack_id=r.material_pack_id,
            link_url=r.link_url,
            created_by=r.created_by,
            created_at=r.created_at,
        )
        for r in rows
    ]


@router.post("/{group_id}/tasks", response_model=TaskOut, status_code=201)
async def create_task(
    group_id: int,
    payload: TaskCreate,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
) -> TaskOut:
    group = await db.get(CommunityStudyGroup, group_id)
    if group is None:
        raise HTTPException(404, "小组不存在")
    member = await db.get(
        CommunityStudyGroupMember, {"group_id": group_id, "user_id": user.id}
    )
    if member is None:
        raise HTTPException(403, "仅成员可发布任务")
    task = CommunityGroupTask(
        group_id=group_id,
        week_id=(payload.week_id or _week_id()).strip()[:16],
        title=payload.title.strip(),
        task_type=(payload.task_type or "shadowing").strip()[:32],
        material_pack_id=payload.material_pack_id,
        link_url=(payload.link_url or None),
        created_by=user.id,
    )
    db.add(task)
    await db.commit()
    await db.refresh(task)
    return TaskOut(
        id=task.id,
        group_id=task.group_id,
        week_id=task.week_id,
        title=task.title,
        task_type=task.task_type,
        material_pack_id=task.material_pack_id,
        link_url=task.link_url,
        created_by=task.created_by,
        created_at=task.created_at,
    )
