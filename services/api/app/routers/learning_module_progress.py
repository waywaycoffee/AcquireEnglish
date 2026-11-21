import json
from typing import Literal
from fastapi import APIRouter, Depends, HTTPException, Response
from pydantic import BaseModel, Field
from sqlalchemy import update
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession
from app.database import get_db
from app.deps import get_current_user
from app.models import LearningModuleProgress, User

Kind = Literal['ipa', 'phonics', 'chunks', 'listening', 'dialogue']
router = APIRouter(prefix='/learning-modules', tags=['learning-modules'])
class State(BaseModel):
    version: Literal[1] = 1
    lesson: int = Field(ge=0, le=999)
    line: int = Field(ge=0, le=99)
    completed: list[int] = Field(default_factory=list, max_length=1000)
class Upload(BaseModel):
    revision: int = Field(ge=0)
    state: State

@router.get('/{kind}/progress')
async def get_progress(kind: Kind, response: Response, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    response.headers['Cache-Control'] = 'no-store'
    row = await db.get(LearningModuleProgress, (user.id, kind))
    return {'revision': row.revision if row else 0, 'state': json.loads(row.payload) if row else None}

@router.put('/{kind}/progress')
async def put_progress(kind: Kind, body: Upload, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    if any(i < 0 or i > 999 for i in body.state.completed): raise HTTPException(422, 'Invalid lesson')
    payload = json.dumps(body.state.model_dump())
    if body.revision == 0:
        db.add(LearningModuleProgress(user_id=user.id,kind=kind,revision=1,payload=payload))
    else:
        changed = await db.execute(update(LearningModuleProgress).where(LearningModuleProgress.user_id == user.id, LearningModuleProgress.kind == kind, LearningModuleProgress.revision == body.revision).values(revision=body.revision + 1,payload=payload))
        if changed.rowcount != 1: raise HTTPException(409, 'Progress changed; reload before saving')
    try: await db.commit()
    except IntegrityError:
        await db.rollback()
        raise HTTPException(409, 'Progress changed; reload before saving')
    return {'revision':body.revision+1,'state':body.state.model_dump()}
