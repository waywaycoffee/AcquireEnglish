"""Cloud FSRS stubs for WeChat mini program (miniprogram-v1 §3.2)."""

from __future__ import annotations

from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field

from app.deps import get_current_user
from app.models import User

router = APIRouter(prefix="/review", tags=["review-cloud"])


class TodaySummaryOut(BaseModel):
    due_count: int = 0
    done_count: int = 0
    streak_days: int = 0
    study_minutes_today: int = 0


class DueItemOut(BaseModel):
    id: str
    key: str
    kind: str = "entry"
    front: str = ""
    back: str = ""
    tts_url: str | None = None
    deep_link: str | None = None


class DueOut(BaseModel):
    items: list[DueItemOut] = Field(default_factory=list)
    total: int = 0


class GradeIn(BaseModel):
    id: str | None = None
    key: str | None = None
    rating: str = Field(pattern=r"^(again|hard|good|easy)$")


class GradeOut(BaseModel):
    next_due_at: str | None = None
    remaining_today: int = 0


@router.get("/today-summary", response_model=TodaySummaryOut)
async def today_summary(user: User = Depends(get_current_user)) -> TodaySummaryOut:
    """Placeholder until cloud FSRS sync ships; keeps mini program home green."""
    _ = user
    return TodaySummaryOut()


@router.get("/due", response_model=DueOut)
async def due_queue(user: User = Depends(get_current_user)) -> DueOut:
    _ = user
    return DueOut()


@router.post("/grade", response_model=GradeOut)
async def grade_item(
    payload: GradeIn, user: User = Depends(get_current_user)
) -> GradeOut:
    _ = (payload, user)
    return GradeOut(remaining_today=0)
