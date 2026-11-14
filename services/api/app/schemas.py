from datetime import datetime

from pydantic import BaseModel, EmailStr, Field


class UserCreate(BaseModel):
    email: EmailStr
    password: str = Field(min_length=6, max_length=128)
    display_name: str | None = Field(default=None, max_length=120)


class UserLogin(BaseModel):
    email: EmailStr
    password: str


class UserOut(BaseModel):
    id: int
    email: EmailStr
    display_name: str | None
    phone: str | None = None
    wechat_bound: bool = False

    model_config = {"from_attributes": True}

    @classmethod
    def from_user(cls, user) -> "UserOut":
        return cls(
            id=user.id,
            email=user.email,
            display_name=user.display_name,
            phone=getattr(user, "phone", None),
            wechat_bound=bool(getattr(user, "wechat_openid", None)),
        )


class TokenOut(BaseModel):
    access_token: str
    token_type: str = "bearer"
    user: UserOut
    is_new_user: bool = False


class SmsSendIn(BaseModel):
    phone: str = Field(min_length=8, max_length=20)


class SmsSendOut(BaseModel):
    ok: bool = True
    expires_in: int
    mock: bool = False
    # Only returned when AUTH_SMS_MOCK=true (dev convenience).
    debug_code: str | None = None


class SmsLoginIn(BaseModel):
    phone: str = Field(min_length=8, max_length=20)
    code: str = Field(min_length=4, max_length=8)


class WechatLoginIn(BaseModel):
    code: str = Field(min_length=2, max_length=128)
    nickname: str | None = Field(default=None, max_length=120)


class SubtitlesOut(BaseModel):
    en: str
    zh: str | None = None


class LessonOut(BaseModel):
    id: str
    title: str
    index: int
    durationSec: float | None = None
    videoUrl: str
    subtitles: SubtitlesOut


class CourseOut(BaseModel):
    id: str
    title: str
    titleZh: str | None = None
    description: str | None = None
    coverUrl: str | None = None
    level: str = "unknown"
    tags: list[str] = []
    lessons: list[LessonOut]


class ProgressUpsert(BaseModel):
    course_id: str
    lesson_id: str
    position_sec: float = Field(ge=0)
    completed: bool = False


class ProgressOut(BaseModel):
    course_id: str
    lesson_id: str
    position_sec: float
    completed: bool
    updated_at: datetime

    model_config = {"from_attributes": True}


class VocabCreate(BaseModel):
    word: str = Field(min_length=1, max_length=120)
    context: str | None = None
    course_id: str | None = None
    lesson_id: str | None = None
    mastery: str = "new"
    ease: float = 2.5
    interval_days: int = 0
    repetitions: int = 0
    due_at: datetime | None = None


class VocabOut(BaseModel):
    id: int
    word: str
    context: str | None
    course_id: str | None
    lesson_id: str | None
    mastery: str
    ease: float = 2.5
    interval_days: int = 0
    repetitions: int = 0
    due_at: datetime | None = None
    created_at: datetime

    model_config = {"from_attributes": True}


class PreferencesUpdate(BaseModel):
    level: str = Field(default="A2", max_length=16)
    tags: list[str] = Field(default_factory=lambda: ["slow", "daily"])
    daily_quota: int = Field(default=2, ge=1, le=10)
    notify_daily_feed: bool = True
    # Empty string clears; omit/null leaves unchanged when using partial-friendly clients.
    # Full QR-login Cookie headers (SESSDATA + buvid + …) often exceed 4KB.
    bilibili_cookie: str | None = Field(default=None, max_length=16384)
    asr_api_key: str | None = Field(default=None, max_length=512)


class PreferencesOut(BaseModel):
    level: str
    tags: list[str]
    daily_quota: int
    notify_daily_feed: bool
    has_bilibili_cookie: bool = False
    has_asr_api_key: bool = False
