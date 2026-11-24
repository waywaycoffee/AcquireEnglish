from datetime import datetime, timedelta, timezone

from jose import JWTError, jwt
from passlib.context import CryptContext

from app.config import settings

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")
ALGORITHM = "HS256"


def hash_password(password: str) -> str:
    return pwd_context.hash(password)


def verify_password(plain: str, hashed: str) -> bool:
    return pwd_context.verify(plain, hashed)


def create_access_token(subject: str, *, session_id: str | None = None) -> str:
    expire = datetime.now(timezone.utc) + timedelta(minutes=settings.access_token_expire_minutes)
    payload: dict[str, object] = {"sub": subject, "exp": expire}
    if session_id:
        payload["sid"] = session_id
    return jwt.encode(
        payload,
        settings.secret_key,
        algorithm=ALGORITHM,
    )


def decode_access_token(token: str) -> str | None:
    subject, _session_id = decode_access_token_full(token)
    return subject


def decode_access_token_full(token: str) -> tuple[str | None, str | None]:
    """Return (email subject, optional session id)."""
    try:
        payload = jwt.decode(token, settings.secret_key, algorithms=[ALGORITHM])
        sub = payload.get("sub")
        sid = payload.get("sid")
        return (str(sub) if sub else None, str(sid) if sid else None)
    except JWTError:
        return (None, None)
