from fastapi import Depends, HTTPException, Query, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.models import User
from app.security import decode_access_token

bearer = HTTPBearer(auto_error=False)


def _user_from_token(token: str | None) -> str | None:
    if not token:
        return None
    return decode_access_token(token)


async def get_current_user_optional(
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer),
    db: AsyncSession = Depends(get_db),
) -> User | None:
    if credentials is None or credentials.scheme.lower() != "bearer":
        return None
    email = decode_access_token(credentials.credentials)
    if not email:
        return None
    result = await db.execute(select(User).where(User.email == email))
    return result.scalar_one_or_none()


async def get_current_user(
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer),
    db: AsyncSession = Depends(get_db),
) -> User:
    user = await get_current_user_optional(credentials=credentials, db=db)
    if user is None:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Not authenticated")
    return user


async def get_current_user_bearer_or_query(
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer),
    token: str | None = Query(default=None, description="JWT for <video>/<audio> src"),
    db: AsyncSession = Depends(get_db),
) -> User:
    """Auth for media endpoints: Authorization bearer OR ?token= (HTML media elements)."""
    raw = None
    if credentials is not None and credentials.scheme.lower() == "bearer":
        raw = credentials.credentials
    elif token:
        raw = token.strip() or None
    email = _user_from_token(raw)
    if not email:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Not authenticated")
    result = await db.execute(select(User).where(User.email == email))
    user = result.scalar_one_or_none()
    if user is None:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Not authenticated")
    return user
