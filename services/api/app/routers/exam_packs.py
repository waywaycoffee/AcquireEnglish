"""Exam practice packs + grading rubric hints."""

from __future__ import annotations

from typing import Any

from fastapi import APIRouter, Depends, HTTPException, Query

from app.deps import get_current_user
from app.models import User
from app.services import exam_packs as packs

router = APIRouter(prefix="/exam", tags=["exam-packs"])


@router.get("/packs")
async def catalog(user: User = Depends(get_current_user)) -> dict[str, Any]:
    del user
    return {"items": packs.list_catalog()}


@router.get("/packs/{family_id}")
async def pack_for_family(
    family_id: str,
    user: User = Depends(get_current_user),
) -> dict[str, Any]:
    del user
    return packs.get_pack(family_id)


@router.get("/packs/{family_id}/section/{skill}")
async def pack_section(
    family_id: str,
    skill: str,
    limit: int = Query(40, ge=1, le=100),
    user: User = Depends(get_current_user),
) -> dict[str, Any]:
    del user
    items = packs.section_items(family_id, skill, limit=limit)
    if not items and skill not in {
        "vocab",
        "listening",
        "reading",
        "writing",
        "speaking",
    }:
        raise HTTPException(status_code=400, detail="unknown skill")
    return {
        "family_id": family_id,
        "skill": skill,
        "items": items,
        "pack": packs.get_pack(family_id),
    }
