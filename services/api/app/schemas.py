from datetime import datetime

from pydantic import BaseModel, EmailStr, Field


class UserCreate(BaseModel):
    email: EmailStr
    password: str = Field(min_length=6, max_length=128)
    display_name: str | None = Field(default=None, max_length=120)
    # Email verification code from /auth/email/send
    code: str = Field(min_length=4, max_length=8)


class UserLogin(BaseModel):
    email: EmailStr
    password: str


class UserOut(BaseModel):
    id: int
    email: EmailStr
    display_name: str | None
    phone: str | None = None
    wechat_bound: bool = False
    points_balance: int = 0

    model_config = {"from_attributes": True}

    @classmethod
    def from_user(cls, user) -> "UserOut":
        return cls(
            id=user.id,
            email=user.email,
            display_name=user.display_name,
            phone=getattr(user, "phone", None),
            wechat_bound=bool(getattr(user, "wechat_openid", None)),
            points_balance=int(getattr(user, "points_balance", 0) or 0),
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


class EmailSendIn(BaseModel):
    email: EmailStr


class EmailSendOut(BaseModel):
    ok: bool = True
    expires_in: int
    mock: bool = False
    # Only returned when AUTH_EMAIL_MOCK=true (dev convenience).
    debug_code: str | None = None


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
    # Client write time for last-write-wins merge across devices.
    client_updated_at: datetime | None = None


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


class FollowedCreator(BaseModel):
    """A Bilibili UP or YouTube channel the user follows for Discover."""

    source: str = Field(pattern=r"^(bilibili|youtube)$")
    creator_id: str = Field(min_length=1, max_length=128)
    display_name: str = Field(default="", max_length=120)
    avatar_url: str | None = Field(default=None, max_length=512)
    profile_url: str | None = Field(default=None, max_length=512)


class PreferencesUpdate(BaseModel):
    level: str = Field(default="A2", max_length=16)
    tags: list[str] = Field(default_factory=lambda: ["slow", "daily"])
    daily_quota: int = Field(default=2, ge=1, le=10)
    notify_daily_feed: bool = True
    # Empty string clears; omit/null leaves unchanged when using partial-friendly clients.
    # Full QR-login Cookie headers (SESSDATA + buvid + …) often exceed 4KB.
    bilibili_cookie: str | None = Field(default=None, max_length=16384)
    asr_api_key: str | None = Field(default=None, max_length=512)
    # None = leave unchanged; list replaces the full follow set.
    followed_creators: list[FollowedCreator] | None = None


class PreferencesOut(BaseModel):
    level: str
    tags: list[str]
    daily_quota: int
    notify_daily_feed: bool
    has_bilibili_cookie: bool = False
    has_asr_api_key: bool = False
    followed_creators: list[FollowedCreator] = Field(default_factory=list)


class CreatorFollowRequest(BaseModel):
    """Follow via space/channel URL, or explicit ids when already known."""

    url: str | None = Field(default=None, max_length=512)
    source: str | None = Field(default=None, pattern=r"^(bilibili|youtube)$")
    creator_id: str | None = Field(default=None, max_length=128)
    display_name: str | None = Field(default=None, max_length=120)
    avatar_url: str | None = Field(default=None, max_length=512)
    profile_url: str | None = Field(default=None, max_length=512)


class CreatorUnfollowRequest(BaseModel):
    source: str = Field(pattern=r"^(bilibili|youtube)$")
    creator_id: str = Field(min_length=1, max_length=128)


class DailyFeedItemOut(BaseModel):
    """Interest-based Bilibili recommendation — not a library course pack."""

    id: str
    bvid: str
    title: str
    author: str = ""
    authorId: str | None = None
    coverUrl: str | None = None
    durationSec: float | None = None
    watchUrl: str
    description: str | None = None
    tags: list[str] = []
    source: str = "bilibili"
    reason: str = "interest"  # interest | followed | english_browse | youtube_browse


class YoutubeBrowseContributeIn(BaseModel):
    """VPN-client discoveries for today's shared YouTube education shelf."""

    level: str = Field(default="A2", max_length=16)
    items: list[DailyFeedItemOut] = Field(default_factory=list, max_length=40)
    replace: bool = False


class YoutubeBrowseMetaOut(BaseModel):
    level: str
    queries: list[str] = Field(default_factory=list)
    day: str


class RecommendedBilibiliVideoOut(BaseModel):
    bvid: str
    title: str
    watch_url: str
    cover_url: str | None = None
    duration_sec: float | None = None
    has_shared_subs: bool = False
    shared_page_count: int = 0


class RecommendedBilibiliCreatorOut(BaseModel):
    """Curated UP + sample videos for the import-study recommendation rail."""

    id: str
    source: str = "bilibili"
    creator_id: str
    display_name: str
    avatar_url: str | None = None
    profile_url: str | None = None
    blurb: str | None = None
    videos: list[RecommendedBilibiliVideoOut] = Field(default_factory=list)


# --- User assets (entitlements / orders / wallet) ---


class ProductSkuOut(BaseModel):
    id: int
    sku_code: str
    kind: str
    title: str
    ref_id: str | None = None
    price_cents: int
    currency: str = "CNY"
    grant_quantity: int | None = None
    duration_days: int | None = None
    active: bool = True

    model_config = {"from_attributes": True}


class EntitlementOut(BaseModel):
    id: int
    asset_kind: str
    asset_ref: str
    source: str
    status: str
    quantity: int | None = None
    starts_at: datetime | None = None
    ends_at: datetime | None = None
    order_id: int | None = None
    created_at: datetime
    updated_at: datetime

    model_config = {"from_attributes": True}


class EntitlementGrantIn(BaseModel):
    asset_kind: str = Field(min_length=2, max_length=32)
    asset_ref: str = Field(min_length=1, max_length=160)
    source: str = Field(default="grant", max_length=24)
    quantity: int | None = Field(default=None, ge=0)
    duration_days: int | None = Field(default=None, ge=1, le=3650)
    meta: dict | None = None


class EntitlementConsumeIn(BaseModel):
    asset_kind: str = Field(min_length=2, max_length=32)
    asset_ref: str = Field(default="", max_length=160)
    quantity: int = Field(default=1, ge=1, le=1000)
    reason: str = Field(default="consume", max_length=64)


class PhraseCreate(BaseModel):
    client_id: str = Field(min_length=1, max_length=120)
    english: str = Field(min_length=1, max_length=2000)
    chinese: str = Field(default="", max_length=2000)
    course: str = Field(default="", max_length=240)
    episode: str = Field(default="", max_length=240)
    time: str = Field(default="", max_length=64)
    course_id: str | None = None
    episode_id: str | None = None
    start_time: str | None = None
    end_time: str | None = None
    note: str | None = None
    rating: int = Field(default=1, ge=1, le=5)
    needs_review: bool = True
    review_count: int = Field(default=0, ge=0)
    lapse_count: int = Field(default=0, ge=0)
    collected_at: datetime | None = None
    last_reviewed_at: datetime | None = None
    next_review_at: datetime | None = None


class PhraseOut(BaseModel):
    id: int
    client_id: str
    english: str
    chinese: str
    course: str
    episode: str
    time: str
    course_id: str | None = None
    episode_id: str | None = None
    start_time: str | None = None
    end_time: str | None = None
    note: str | None = None
    rating: int
    needs_review: bool
    review_count: int
    lapse_count: int
    collected_at: datetime | None = None
    last_reviewed_at: datetime | None = None
    next_review_at: datetime | None = None
    created_at: datetime
    updated_at: datetime

    model_config = {"from_attributes": True}


class OrderItemIn(BaseModel):
    sku_code: str = Field(min_length=1, max_length=64)
    quantity: int = Field(default=1, ge=1, le=99)


class OrderCreateIn(BaseModel):
    coupon_id: int | None = None
    items: list[OrderItemIn] = Field(min_length=1)
    provider: str = Field(default="mock", max_length=24)
    # For module.combo.any2.* — client picks N module codes.
    selected_modules: list[str] | None = None


class OrderItemOut(BaseModel):
    sku_id: int
    sku_code: str
    quantity: int
    unit_price_cents: int


class OrderOut(BaseModel):
    id: int
    status: str
    provider: str
    provider_ref: str | None = None
    amount_cents: int
    currency: str
    items: list[OrderItemOut]
    created_at: datetime
    paid_at: datetime | None = None


class WeChatAppPrepayOut(BaseModel):
    order_id: int
    out_trade_no: str
    app_id: str
    partner_id: str
    prepay_id: str
    package_value: str
    nonce_str: str
    timestamp: int
    sign: str
    sign_type: str = "RSA"


class WalletOut(BaseModel):
    balance_credits: int
    updated_at: datetime | None = None


class UserAssetsOut(BaseModel):
    entitlements: list[EntitlementOut]
    wallet: WalletOut
    link_course_count: int
    vocab_count: int
    active_membership: str | None = None
    unlocked_modules: list[str] = []
