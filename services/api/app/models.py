from datetime import date, datetime

from sqlalchemy import (
    BigInteger,
    Boolean,
    Date,
    DateTime,
    Float,
    ForeignKey,
    Index,
    Integer,
    JSON,
    String,
    Text,
    UniqueConstraint,
    func,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base


class BilibiliAuthorization(Base):
    __tablename__ = "bilibili_authorizations"

    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), primary_key=True)
    state_hash: Mapped[str | None] = mapped_column(String(64), unique=True)
    state_expires: Mapped[int] = mapped_column(BigInteger, default=0)
    verified: Mapped[bool] = mapped_column(Boolean, default=False)


class User(Base):
    __tablename__ = "users"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    email: Mapped[str] = mapped_column(String(255), unique=True, index=True)
    hashed_password: Mapped[str] = mapped_column(String(255))
    display_name: Mapped[str | None] = mapped_column(String(120), nullable=True)
    phone: Mapped[str | None] = mapped_column(String(32), unique=True, index=True, nullable=True)
    wechat_openid: Mapped[str | None] = mapped_column(
        String(64), unique=True, index=True, nullable=True
    )
    wechat_mp_openid: Mapped[str | None] = mapped_column(
        String(64), unique=True, index=True, nullable=True
    )
    wechat_unionid: Mapped[str | None] = mapped_column(
        String(64), unique=True, index=True, nullable=True
    )
    points_balance: Mapped[int] = mapped_column(Integer, default=0)
    # Short share/referral code for Moments download QR attribution.
    invite_code: Mapped[str | None] = mapped_column(
        String(16), unique=True, index=True, nullable=True
    )
    # Public registration serial (AE-000123), assigned once from autoincrement id.
    member_no: Mapped[str | None] = mapped_column(
        String(16), unique=True, index=True, nullable=True
    )
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())

    progresses: Mapped[list["LessonProgress"]] = relationship(back_populates="user")
    vocab_items: Mapped[list["VocabItem"]] = relationship(back_populates="user")
    phrase_items: Mapped[list["PhraseItem"]] = relationship(back_populates="user")
    preference: Mapped["UserPreference | None"] = relationship(
        back_populates="user", uselist=False
    )
    link_courses: Mapped[list["UserLinkCourse"]] = relationship(back_populates="user")
    netdisk_bindings: Mapped[list["UserNetdiskBinding"]] = relationship(
        back_populates="user"
    )
    entitlements: Mapped[list["UserEntitlement"]] = relationship(back_populates="user")
    orders: Mapped[list["Order"]] = relationship(back_populates="user")
    wallet: Mapped["WalletAccount | None"] = relationship(
        back_populates="user", uselist=False
    )
    points_ledger: Mapped[list["UserPointsLedger"]] = relationship(back_populates="user")


class UserNetdiskBinding(Base):
    """User's own Baidu / Quark drive bound via OpenList (no share-link import)."""

    __tablename__ = "user_netdisk_bindings"
    __table_args__ = (
        UniqueConstraint("user_id", "provider", name="uq_user_netdisk_provider"),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    # baidu | quark
    provider: Mapped[str] = mapped_column(String(16), index=True)
    # Fernet token of the cookie / refresh material (never return raw to clients).
    credential_enc: Mapped[str] = mapped_column(Text)
    openlist_mount_path: Mapped[str] = mapped_column(String(255))
    openlist_storage_id: Mapped[int | None] = mapped_column(Integer, nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )

    user: Mapped[User] = relationship(back_populates="netdisk_bindings")


class UserPointsLedger(Base):
    __tablename__ = "user_points_ledger"
    __table_args__ = (
        UniqueConstraint("user_id", "client_share_id", name="uq_user_client_share"),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    delta: Mapped[int] = mapped_column(Integer)
    reason: Mapped[str] = mapped_column(String(64), index=True)
    ref: Mapped[str | None] = mapped_column(String(255), nullable=True)
    client_share_id: Mapped[str] = mapped_column(String(128), index=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())

    user: Mapped[User] = relationship(back_populates="points_ledger")


class ReferralInstall(Base):
    """One successful install/register attribution per invitee."""

    __tablename__ = "referral_installs"
    __table_args__ = (
        UniqueConstraint("invitee_user_id", name="uq_referral_invitee"),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    referrer_user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    invitee_user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    invite_code: Mapped[str] = mapped_column(String(16), index=True)
    points_awarded: Mapped[int] = mapped_column(Integer, default=0)
    pro_days_awarded: Mapped[int] = mapped_column(Integer, default=0)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )


class LessonProgress(Base):
    __tablename__ = "lesson_progress"
    __table_args__ = (UniqueConstraint("user_id", "lesson_id", name="uq_user_lesson"),)

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    course_id: Mapped[str] = mapped_column(String(120), index=True)
    lesson_id: Mapped[str] = mapped_column(String(120), index=True)
    position_sec: Mapped[float] = mapped_column(Float, default=0.0)
    completed: Mapped[int] = mapped_column(Integer, default=0)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )

    user: Mapped[User] = relationship(back_populates="progresses")


class VocabItem(Base):
    __tablename__ = "vocab_items"
    __table_args__ = (UniqueConstraint("user_id", "word", "lesson_id", name="uq_user_word_lesson"),)

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    word: Mapped[str] = mapped_column(String(120), index=True)
    context: Mapped[str | None] = mapped_column(Text, nullable=True)
    course_id: Mapped[str | None] = mapped_column(String(120), nullable=True)
    lesson_id: Mapped[str | None] = mapped_column(String(120), nullable=True)
    mastery: Mapped[str] = mapped_column(String(32), default="new")
    ease: Mapped[float] = mapped_column(Float, default=2.5)
    interval_days: Mapped[int] = mapped_column(Integer, default=0)
    repetitions: Mapped[int] = mapped_column(Integer, default=0)
    due_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )

    user: Mapped[User] = relationship(back_populates="vocab_items")


class PhraseItem(Base):
    __tablename__ = "phrase_items"
    __table_args__ = (
        UniqueConstraint("user_id", "client_id", name="uq_user_phrase_client"),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    client_id: Mapped[str] = mapped_column(String(120), index=True)
    english: Mapped[str] = mapped_column(Text)
    chinese: Mapped[str] = mapped_column(Text, default="")
    course: Mapped[str] = mapped_column(String(240), default="")
    episode: Mapped[str] = mapped_column(String(240), default="")
    time: Mapped[str] = mapped_column(String(64), default="")
    course_id: Mapped[str | None] = mapped_column(String(120), nullable=True)
    episode_id: Mapped[str | None] = mapped_column(String(120), nullable=True)
    start_time: Mapped[str | None] = mapped_column(String(64), nullable=True)
    end_time: Mapped[str | None] = mapped_column(String(64), nullable=True)
    note: Mapped[str | None] = mapped_column(Text, nullable=True)
    rating: Mapped[int] = mapped_column(Integer, default=1)
    needs_review: Mapped[int] = mapped_column(Integer, default=1)
    review_count: Mapped[int] = mapped_column(Integer, default=0)
    lapse_count: Mapped[int] = mapped_column(Integer, default=0)
    collected_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    last_reviewed_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    next_review_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )

    user: Mapped[User] = relationship(back_populates="phrase_items")


class UserPreference(Base):
    __tablename__ = "user_preferences"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), unique=True, index=True
    )
    level: Mapped[str] = mapped_column(String(16), default="A2")
    tags_json: Mapped[str] = mapped_column(Text, default='["slow","daily"]')
    daily_quota: Mapped[int] = mapped_column(Integer, default=2)
    notify_daily_feed: Mapped[int] = mapped_column(Integer, default=1)
    # Optional user-provided Bilibili cookie for login-gated CC/AI subtitles.
    bilibili_cookie: Mapped[str | None] = mapped_column(Text, nullable=True)
    # Optional per-user DashScope / 百炼 API key for web AI subtitles.
    asr_api_key: Mapped[str | None] = mapped_column(Text, nullable=True)
    # JSON list of followed creators: [{source, creator_id, display_name, ...}].
    followed_creators_json: Mapped[str] = mapped_column(Text, default="[]")
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )

    user: Mapped[User] = relationship(back_populates="preference")


class SharedOcrBook(Base):
    """Community cache of OCR'd scanned PDF / ebook text keyed by file sha256."""

    __tablename__ = "shared_ocr_books"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    content_sha256: Mapped[str] = mapped_column(String(64), unique=True, index=True)
    title: Mapped[str] = mapped_column(String(255), default="")
    source_filename: Mapped[str] = mapped_column(String(255), default="")
    plain_text: Mapped[str] = mapped_column(Text)
    page_count: Mapped[int] = mapped_column(Integer, default=0)
    char_count: Mapped[int] = mapped_column(Integer, default=0)
    word_count: Mapped[int] = mapped_column(Integer, default=0)
    quality_score: Mapped[float] = mapped_column(Float, default=0.0)
    source_origin: Mapped[str] = mapped_column(String(32), default="ocr")
    uploader_user_id: Mapped[int | None] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL"), nullable=True, index=True
    )
    hit_count: Mapped[int] = mapped_column(Integer, default=0)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )


class SharedBilibiliSubtitle(Base):
    """Community cache of filled EN/ZH softsubs keyed by Bilibili episode."""

    __tablename__ = "shared_bilibili_subtitles"
    __table_args__ = (
        UniqueConstraint("bvid", "page", name="uq_shared_bili_bvid_page"),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    bvid: Mapped[str] = mapped_column(String(32), index=True)
    page: Mapped[int] = mapped_column(Integer, default=1)
    # Bilibili cid can exceed int32 on newer uploads.
    cid: Mapped[int | None] = mapped_column(BigInteger, nullable=True, index=True)
    duration_sec: Mapped[int | None] = mapped_column(Integer, nullable=True)
    # Human-readable identity (video title · 分P part). Filled on upsert/backfill.
    title: Mapped[str] = mapped_column(String(512), default="")
    # Short Chinese cue preview so learners recognize content without opening SRT.
    preview_zh: Mapped[str] = mapped_column(String(512), default="")
    subtitle_en_srt: Mapped[str] = mapped_column(Text)
    subtitle_zh_srt: Mapped[str | None] = mapped_column(Text, nullable=True)
    quality_score: Mapped[float] = mapped_column(Float, default=0.0)
    cue_count: Mapped[int] = mapped_column(Integer, default=0)
    en_hits: Mapped[int] = mapped_column(Integer, default=0)
    zh_hits: Mapped[int] = mapped_column(Integer, default=0)
    uploader_user_id: Mapped[int | None] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL"), nullable=True, index=True
    )
    source_origin: Mapped[str] = mapped_column(String(32), default="asr")
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )


class SharedMediaSubtitle(Base):
    """Reusable subtitle pack keyed by a real media-file fingerprint.

    ``file_hash`` stores the four-block Shooter/subfinder fingerprint.  Unlike
    the Bilibili cache this works for MKV/MP4 files from a user's own netdisk.
    """

    __tablename__ = "shared_media_subtitles"
    __table_args__ = (
        UniqueConstraint(
            "file_hash", "language", name="uq_shared_media_hash_language"
        ),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    file_hash: Mapped[str] = mapped_column(String(160), index=True)
    file_size: Mapped[int | None] = mapped_column(BigInteger, nullable=True, index=True)
    duration_sec: Mapped[int | None] = mapped_column(Integer, nullable=True)
    title: Mapped[str] = mapped_column(String(512), default="")
    season: Mapped[int | None] = mapped_column(Integer, nullable=True)
    episode: Mapped[int | None] = mapped_column(Integer, nullable=True)
    language: Mapped[str] = mapped_column(String(16), default="en")
    subtitle_srt: Mapped[str] = mapped_column(Text)
    cue_count: Mapped[int] = mapped_column(Integer, default=0)
    quality_score: Mapped[float] = mapped_column(Float, default=0.0)
    source_origin: Mapped[str] = mapped_column(String(32), default="subfinder")
    source_ref: Mapped[str] = mapped_column(String(1024), default="")
    hit_count: Mapped[int] = mapped_column(Integer, default=0)
    uploader_user_id: Mapped[int | None] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL"), nullable=True, index=True
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )


class UserLinkCourse(Base):
    """YouTube / Bilibili paste-link imports owned by a user."""

    __tablename__ = "user_link_courses"
    __table_args__ = (
        UniqueConstraint("user_id", "source", "external_id", name="uq_user_link_source_ext"),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    source: Mapped[str] = mapped_column(String(32), index=True)  # youtube | bilibili
    external_id: Mapped[str] = mapped_column(String(64), index=True)
    title: Mapped[str] = mapped_column(String(512))
    author: Mapped[str | None] = mapped_column(String(255), nullable=True)
    watch_url: Mapped[str] = mapped_column(String(1024))
    duration_sec: Mapped[int] = mapped_column(Integer, default=60)
    subtitle_en_srt: Mapped[str | None] = mapped_column(Text, nullable=True)
    subtitle_zh_srt: Mapped[str | None] = mapped_column(Text, nullable=True)
    # CDN / remote poster URL (Bilibili pic, YouTube thumb, etc.).
    cover_url: Mapped[str | None] = mapped_column(String(1024), nullable=True)
    # Local/custom poster bytes as base64 so new devices can restore without CDN.
    cover_image_base64: Mapped[str | None] = mapped_column(Text, nullable=True)
    # Netdisk TV-series grouping: same key → one multi-lesson CourseOut.
    series_key: Mapped[str | None] = mapped_column(String(64), nullable=True, index=True)
    series_title: Mapped[str | None] = mapped_column(String(512), nullable=True)
    episode_index: Mapped[int | None] = mapped_column(Integer, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())

    user: Mapped[User] = relationship(back_populates="link_courses")


class ProductSku(Base):
    """Sellable / grantable catalog SKU for user assets."""

    __tablename__ = "product_skus"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    sku_code: Mapped[str] = mapped_column(String(64), unique=True, index=True)
    # course_pack | membership | coach_minutes | digital_human_minutes | vocab_pack | credits
    kind: Mapped[str] = mapped_column(String(32), index=True)
    title: Mapped[str] = mapped_column(String(255))
    # Optional catalog ref (course_id / pack_id / plan code).
    ref_id: Mapped[str | None] = mapped_column(String(120), nullable=True, index=True)
    price_cents: Mapped[int] = mapped_column(Integer, default=0)
    currency: Mapped[str] = mapped_column(String(8), default="CNY")
    # Consumable grant amount (minutes / credits); null = unlimited license.
    grant_quantity: Mapped[int | None] = mapped_column(Integer, nullable=True)
    # Days of validity after grant; null = no expiry.
    duration_days: Mapped[int | None] = mapped_column(Integer, nullable=True)
    meta_json: Mapped[str] = mapped_column(Text, default="{}")
    active: Mapped[int] = mapped_column(Integer, default=1)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


class Order(Base):
    __tablename__ = "orders"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    # pending | paid | refunded | failed | cancelled
    status: Mapped[str] = mapped_column(String(24), default="pending", index=True)
    # wechat | apple | google | manual | mock
    provider: Mapped[str] = mapped_column(String(24), default="manual")
    provider_ref: Mapped[str | None] = mapped_column(String(128), nullable=True, index=True)
    amount_cents: Mapped[int] = mapped_column(Integer, default=0)
    currency: Mapped[str] = mapped_column(String(8), default="CNY")
    meta_json: Mapped[str] = mapped_column(Text, default="{}")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    paid_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)

    user: Mapped[User] = relationship(back_populates="orders")
    items: Mapped[list["OrderItem"]] = relationship(
        back_populates="order", cascade="all, delete-orphan"
    )


class OrderItem(Base):
    __tablename__ = "order_items"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    order_id: Mapped[int] = mapped_column(ForeignKey("orders.id", ondelete="CASCADE"), index=True)
    sku_id: Mapped[int] = mapped_column(ForeignKey("product_skus.id", ondelete="RESTRICT"), index=True)
    quantity: Mapped[int] = mapped_column(Integer, default=1)
    unit_price_cents: Mapped[int] = mapped_column(Integer, default=0)

    order: Mapped[Order] = relationship(back_populates="items")
    sku: Mapped[ProductSku] = relationship()


class UserEntitlement(Base):
    """Core user asset / license / quota row."""

    __tablename__ = "user_entitlements"
    __table_args__ = (
        UniqueConstraint(
            "user_id",
            "asset_kind",
            "asset_ref",
            name="uq_user_asset_kind_ref",
        ),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    # course_access | course_pack | link_import | vocab_pack |
    # membership | coach_quota | digital_human_quota | credits
    asset_kind: Mapped[str] = mapped_column(String(32), index=True)
    asset_ref: Mapped[str] = mapped_column(String(160), index=True)
    # purchase | grant | import | promo | system
    source: Mapped[str] = mapped_column(String(24), default="system")
    order_id: Mapped[int | None] = mapped_column(
        ForeignKey("orders.id", ondelete="SET NULL"), nullable=True, index=True
    )
    # active | expired | revoked
    status: Mapped[str] = mapped_column(String(24), default="active", index=True)
    # Remaining units for consumables; null = unlimited.
    quantity: Mapped[int | None] = mapped_column(Integer, nullable=True)
    starts_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    ends_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    meta_json: Mapped[str] = mapped_column(Text, default="{}")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )

    user: Mapped[User] = relationship(back_populates="entitlements")


class WalletAccount(Base):
    __tablename__ = "wallet_accounts"

    user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), primary_key=True
    )
    balance_credits: Mapped[int] = mapped_column(Integer, default=0)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )

    user: Mapped[User] = relationship(back_populates="wallet")


class WalletLedger(Base):
    __tablename__ = "wallet_ledger"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    delta: Mapped[int] = mapped_column(Integer)
    reason: Mapped[str] = mapped_column(String(64), default="adjust")
    order_id: Mapped[int | None] = mapped_column(
        ForeignKey("orders.id", ondelete="SET NULL"), nullable=True, index=True
    )
    meta_json: Mapped[str] = mapped_column(Text, default="{}")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


class ReviewBackup(Base):
    __tablename__ = "review_backups"

    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), primary_key=True)
    revision: Mapped[int] = mapped_column(Integer, nullable=False)
    payload: Mapped[str] = mapped_column(Text, nullable=False)


class ReadingLibraryBackup(Base):
    """Versioned reading shelf + progress + vocab lists for cross-device restore."""

    __tablename__ = "reading_library_backups"

    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), primary_key=True)
    revision: Mapped[int] = mapped_column(Integer, nullable=False)
    payload: Mapped[str] = mapped_column(Text, nullable=False)


class WordbookBackup(Base):
    """Full word book (favorites + non-favorites) for cross-device restore."""

    __tablename__ = "wordbook_backups"

    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), primary_key=True)
    revision: Mapped[int] = mapped_column(Integer, nullable=False)
    payload: Mapped[str] = mapped_column(Text, nullable=False)


class AppSettingsBackup(Base):
    """Learning settings + word-review prefs (device-local keys stripped client-side)."""

    __tablename__ = "app_settings_backups"

    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), primary_key=True)
    revision: Mapped[int] = mapped_column(Integer, nullable=False)
    payload: Mapped[str] = mapped_column(Text, nullable=False)


class CommunityPost(Base):
    """User-generated community posts (team_invite / share_bilibili / feedback)."""

    __tablename__ = "community_posts"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    # team_invite | share_bilibili | feedback
    # legacy: method | share_link | podcast_placeholder
    kind: Mapped[str] = mapped_column(String(32), index=True)
    title: Mapped[str] = mapped_column(String(200), default="")
    body: Mapped[str] = mapped_column(Text, default="")
    link_url: Mapped[str | None] = mapped_column(String(1024), nullable=True)
    link_title: Mapped[str | None] = mapped_column(String(512), nullable=True)
    link_cover: Mapped[str | None] = mapped_column(String(1024), nullable=True)
    bvid: Mapped[str | None] = mapped_column(String(32), nullable=True, index=True)
    interest_tag: Mapped[str | None] = mapped_column(String(32), nullable=True, index=True)
    english_level: Mapped[str | None] = mapped_column(String(16), nullable=True, index=True)
    # Optional embeds: {"embed_word":"apple","embed_timestamp_sec":12.5,"quote":"..."}
    meta_json: Mapped[str] = mapped_column(Text, default="{}")
    like_count: Mapped[int] = mapped_column(Integer, default=0)
    comment_count: Mapped[int] = mapped_column(Integer, default=0)
    # visible | hidden
    status: Mapped[str] = mapped_column(String(16), default="visible", index=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )


class CommunityComment(Base):
    __tablename__ = "community_comments"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    post_id: Mapped[int] = mapped_column(
        ForeignKey("community_posts.id", ondelete="CASCADE"), index=True
    )
    user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    body: Mapped[str] = mapped_column(Text)
    mirrored_to_bilibili: Mapped[int] = mapped_column(Integer, default=0)
    bili_rpid: Mapped[str | None] = mapped_column(String(64), nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )


class CommunityReclassifyRequest(Base):
    __tablename__ = "community_reclassify_requests"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    post_id: Mapped[int] = mapped_column(
        ForeignKey("community_posts.id", ondelete="CASCADE"), index=True
    )
    user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    suggested_interest_tag: Mapped[str] = mapped_column(String(32))
    suggested_english_level: Mapped[str] = mapped_column(String(16))
    reason: Mapped[str] = mapped_column(Text, default="")
    # pending | approved | rejected
    status: Mapped[str] = mapped_column(String(16), default="pending", index=True)
    reviewed_by: Mapped[int | None] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL"), nullable=True
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
    reviewed_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )


class CommunityPostLike(Base):
    __tablename__ = "community_post_likes"
    __table_args__ = (
        UniqueConstraint("post_id", "user_id", name="uq_community_post_like"),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    post_id: Mapped[int] = mapped_column(
        ForeignKey("community_posts.id", ondelete="CASCADE"), index=True
    )
    user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )


class CommunityContentEngage(Base):
    """One row per user/day/content — powers community 「热门」 rankings."""

    __tablename__ = "community_content_engages"
    __table_args__ = (
        UniqueConstraint(
            "user_id",
            "day",
            "content_key",
            name="uq_content_engage_user_day_key",
        ),
        Index("idx_content_engage_day_type", "day", "content_type"),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    # YYYY-MM-DD (client local calendar day).
    day: Mapped[str] = mapped_column(String(10), index=True)
    # video | book
    content_type: Mapped[str] = mapped_column(String(16), index=True)
    content_key: Mapped[str] = mapped_column(String(256), index=True)
    title: Mapped[str] = mapped_column(String(300), default="")
    cover_url: Mapped[str] = mapped_column(String(1024), default="")
    open_url: Mapped[str] = mapped_column(String(1024), default="")
    # bilibili | import | netdisk | upload | reading
    source: Mapped[str] = mapped_column(String(32), default="import")
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )


class UserStudyStatsDaily(Base):
    """Per-user daily study seconds + vocab snapshot for leaderboards."""

    __tablename__ = "user_study_stats_daily"
    __table_args__ = (
        UniqueConstraint("user_id", "day", name="uq_user_study_day"),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    # YYYY-MM-DD in client local calendar (or UTC day string from client).
    day: Mapped[str] = mapped_column(String(10), index=True)
    study_seconds: Mapped[int] = mapped_column(Integer, default=0)
    vocab_count: Mapped[int] = mapped_column(Integer, default=0)
    # Today learning-star metrics (monotonic max on upsert).
    video_count: Mapped[int] = mapped_column(Integer, default=0)
    video_seconds: Mapped[int] = mapped_column(Integer, default=0)
    reading_seconds: Mapped[int] = mapped_column(Integer, default=0)
    vocab_seconds: Mapped[int] = mapped_column(Integer, default=0)
    vocab_learned_count: Mapped[int] = mapped_column(Integer, default=0)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )


class CommunityProfile(Base):
    __tablename__ = "community_profiles"

    user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), primary_key=True
    )
    bio: Mapped[str] = mapped_column(String(280), default="")
    looking_for_partner: Mapped[int] = mapped_column(Integer, default=0)
    show_on_leaderboard: Mapped[int] = mapped_column(Integer, default=1)
    english_level: Mapped[str | None] = mapped_column(String(16), nullable=True)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )


class UserReviewPoints(Base):
    """Spendable review points for avatar cosmetics (separate from share points)."""

    __tablename__ = "user_review_points"

    user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), primary_key=True
    )
    balance: Mapped[int] = mapped_column(Integer, default=0)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )


class ReviewPointsLedger(Base):
    __tablename__ = "review_points_ledger"
    __table_args__ = (
        UniqueConstraint("user_id", "client_event_id", name="uq_review_points_event"),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    delta: Mapped[int] = mapped_column(Integer)
    reason: Mapped[str] = mapped_column(String(64), index=True)
    client_event_id: Mapped[str] = mapped_column(String(128), index=True)
    meta_json: Mapped[str] = mapped_column(Text, default="{}")
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )


class CosmeticItem(Base):
    __tablename__ = "cosmetic_items"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    sku: Mapped[str] = mapped_column(String(64), unique=True, index=True)
    # body | hair | top | bottom | accessory | bg
    slot: Mapped[str] = mapped_column(String(24), index=True)
    title: Mapped[str] = mapped_column(String(120))
    price_points: Mapped[int] = mapped_column(Integer, default=0)
    asset_key: Mapped[str] = mapped_column(String(120), default="")
    preview_url: Mapped[str | None] = mapped_column(String(512), nullable=True)
    active: Mapped[int] = mapped_column(Integer, default=1)
    sort_order: Mapped[int] = mapped_column(Integer, default=0)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )


class UserCosmeticInventory(Base):
    __tablename__ = "user_cosmetic_inventory"
    __table_args__ = (
        UniqueConstraint("user_id", "sku", name="uq_user_cosmetic_sku"),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    sku: Mapped[str] = mapped_column(String(64), index=True)
    acquired_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )


class UserAvatarLoadout(Base):
    __tablename__ = "user_avatar_loadout"
    __table_args__ = (
        UniqueConstraint("user_id", "slot", name="uq_user_avatar_slot"),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    slot: Mapped[str] = mapped_column(String(24))
    sku: Mapped[str] = mapped_column(String(64))
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )


class VocabPkChallenge(Base):
    __tablename__ = "vocab_pk_challenges"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    challenger_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    opponent_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    # pending | completed | declined
    status: Mapped[str] = mapped_column(String(16), default="pending", index=True)
    challenger_vocab: Mapped[int] = mapped_column(Integer, default=0)
    opponent_vocab: Mapped[int] = mapped_column(Integer, default=0)
    winner_id: Mapped[int | None] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL"), nullable=True
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
    completed_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )


class MembershipCoupon(Base):
    __tablename__ = "membership_coupons"
    __table_args__ = (UniqueConstraint("user_id", "reward_code", name="uq_member_reward"),)
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True)
    reward_code: Mapped[str] = mapped_column(String(64))
    kind: Mapped[str] = mapped_column(String(16))
    value: Mapped[int] = mapped_column(Integer)
    used: Mapped[int] = mapped_column(Integer, default=0)


class UserLoginDay(Base):
    """UTC calendar days the user authenticated (for trial-extend streak)."""

    __tablename__ = "user_login_days"
    __table_args__ = (
        UniqueConstraint("user_id", "day", name="uq_user_login_day"),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    # YYYY-MM-DD (UTC)
    day: Mapped[str] = mapped_column(String(10), index=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )


class PointsLedger(Base):
    """Study-points earn/spend log (PRD 积分经济; balance lives on wallet)."""

    __tablename__ = "points_ledger"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    delta: Mapped[int] = mapped_column(Integer)
    # earn | spend | expire | adjust
    direction: Mapped[str] = mapped_column(String(16), default="earn", index=True)
    reason: Mapped[str] = mapped_column(String(64), index=True)
    meta_json: Mapped[str] = mapped_column(Text, default="{}")
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), index=True
    )


class UsageCounter(Base):
    """Rolling usage meters for free-tier / module quotas."""

    __tablename__ = "usage_counters"
    __table_args__ = (
        UniqueConstraint(
            "user_id", "metric", "period_key", name="uq_usage_user_metric_period"
        ),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    metric: Mapped[str] = mapped_column(String(32), index=True)
    period_key: Mapped[str] = mapped_column(String(24), index=True)
    count: Mapped[int] = mapped_column(Integer, default=0)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )


class RankState(Base):
    """学力值 / 段位 / 赛季榜分 (separate from points wallet)."""

    __tablename__ = "rank_state"

    user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), primary_key=True
    )
    power_points: Mapped[int] = mapped_column(Integer, default=0)
    tier: Mapped[str] = mapped_column(String(24), default="bronze", index=True)
    season_id: Mapped[str] = mapped_column(String(32), default="S1", index=True)
    season_score: Mapped[int] = mapped_column(Integer, default=0)
    checkin_streak: Mapped[int] = mapped_column(Integer, default=0)
    last_checkin_day: Mapped[str | None] = mapped_column(String(10), nullable=True)
    arena_extra: Mapped[int] = mapped_column(Integer, default=0)
    arena_used_today: Mapped[int] = mapped_column(Integer, default=0)
    arena_day: Mapped[str | None] = mapped_column(String(10), nullable=True)
    arena_win_streak: Mapped[int] = mapped_column(Integer, default=0)
    meta_json: Mapped[str] = mapped_column(Text, default="{}")
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )


class CommerceEvent(Base):
    """Paywall / purchase / trial funnel events."""

    __tablename__ = "commerce_events"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    user_id: Mapped[int | None] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL"), nullable=True, index=True
    )
    event: Mapped[str] = mapped_column(String(64), index=True)
    module: Mapped[str | None] = mapped_column(String(64), nullable=True, index=True)
    page: Mapped[str | None] = mapped_column(String(120), nullable=True)
    meta_json: Mapped[str] = mapped_column(Text, default="{}")
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), index=True
    )


class DeskInvite(Base):
    __tablename__ = "desk_invites"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    sender_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    target_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    status: Mapped[str] = mapped_column(String(16), default="pending")
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


class DeskMember(Base):
    __tablename__ = "desk_members"
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), primary_key=True)
    desk_id: Mapped[int] = mapped_column(ForeignKey("desk_invites.id", ondelete="CASCADE"), index=True)
    share_activity: Mapped[int] = mapped_column(Integer, default=0)
    share_videos: Mapped[int] = mapped_column(Integer, default=0)
    share_library: Mapped[int] = mapped_column(Integer, default=0)


class DeskBlock(Base):
    __tablename__ = "desk_blocks"
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), primary_key=True)
    blocked_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), primary_key=True)


class DeskLibraryWord(Base):
    __tablename__ = "desk_library_words"
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), primary_key=True)
    word: Mapped[str] = mapped_column(String(120), primary_key=True)


class DeskLibrarySnapshot(Base):
    __tablename__ = "desk_library_snapshots"
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), primary_key=True)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


class DeskPkPermission(Base):
    __tablename__ = "desk_pk_permissions"
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), primary_key=True)
    desk_id: Mapped[int] = mapped_column(Integer)
    enabled: Mapped[int] = mapped_column(Integer, default=0)


class DeskWordPk(Base):
    __tablename__ = "desk_word_pks"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    desk_id: Mapped[int] = mapped_column(Integer, index=True)
    active_desk_id: Mapped[int | None] = mapped_column(Integer, nullable=True, unique=True)
    sender_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    target_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    status: Mapped[str] = mapped_column(String(16), default="pending")
    days: Mapped[int] = mapped_column(Integer)
    questions_json: Mapped[str] = mapped_column(Text)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


class DeskPkRun(Base):
    __tablename__ = "desk_pk_runs"
    match_id: Mapped[int] = mapped_column(ForeignKey("desk_word_pks.id", ondelete="CASCADE"), primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), primary_key=True)
    next_index: Mapped[int] = mapped_column(Integer, default=0)
    question_started_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)


class DeskPkAnswer(Base):
    __tablename__ = "desk_pk_answers"
    match_id: Mapped[int] = mapped_column(ForeignKey("desk_word_pks.id", ondelete="CASCADE"), primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), primary_key=True)
    question_index: Mapped[int] = mapped_column(Integer, primary_key=True)
    choice: Mapped[int | None] = mapped_column(Integer, nullable=True)
    correct: Mapped[int] = mapped_column(Integer)


class StudyActivityClock(Base):
    __tablename__ = "study_activity_clocks"
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), primary_key=True)
    first_seen: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    last_tick: Mapped[datetime] = mapped_column(DateTime(timezone=True))


class StudyRewardDay(Base):
    __tablename__ = "study_reward_days"
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), primary_key=True)
    day: Mapped[str] = mapped_column(String(10), primary_key=True)
    seconds: Mapped[int] = mapped_column(Integer, default=0)
    review_target: Mapped[int] = mapped_column(Integer, default=5)
    target_locked: Mapped[int] = mapped_column(Integer, default=0)


class StudyReviewEvidence(Base):
    __tablename__ = "study_review_evidence"
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), primary_key=True)
    day: Mapped[str] = mapped_column(String(10), primary_key=True)
    card_key: Mapped[str] = mapped_column(String(240), primary_key=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


class StudyCheckin(Base):
    __tablename__ = "study_checkins"
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), primary_key=True)
    day: Mapped[str] = mapped_column(String(10), primary_key=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


class DeskQuestWeek(Base):
    """Optional weekly co-op practice counts (solo chapter progress stays local/personal)."""

    __tablename__ = "desk_quest_weeks"
    user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), primary_key=True
    )
    week_id: Mapped[str] = mapped_column(String(16), primary_key=True)
    chapter: Mapped[str] = mapped_column(String(32), primary_key=True)
    levels_json: Mapped[str] = mapped_column(Text, default="[]")
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )


class ChallengeFirstClear(Base):
    """First clear timestamp per user/chapter/level for delayed retest."""

    __tablename__ = "challenge_first_clears"
    user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), primary_key=True
    )
    chapter: Mapped[str] = mapped_column(String(32), primary_key=True)
    level: Mapped[int] = mapped_column(Integer, primary_key=True)
    cleared_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))


class ChallengeRetest(Base):
    """Delayed retest attempts after first clear (>=1 day)."""

    __tablename__ = "challenge_retests"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    chapter: Mapped[str] = mapped_column(String(32), index=True)
    level: Mapped[int] = mapped_column(Integer)
    passed: Mapped[int] = mapped_column(Integer, default=1)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )


class ChallengePostStat(Base):
    """Open / complete counters for challenge-linked community posts."""

    __tablename__ = "challenge_post_stats"
    post_id: Mapped[int] = mapped_column(
        ForeignKey("community_posts.id", ondelete="CASCADE"), primary_key=True
    )
    opens: Mapped[int] = mapped_column(Integer, default=0)
    completes: Mapped[int] = mapped_column(Integer, default=0)


class CommunityMaterialPack(Base):
    """Shareable learning material pack (metadata + fork; no video bytes)."""

    __tablename__ = "community_material_packs"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    owner_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    title: Mapped[str] = mapped_column(String(200), default="")
    description: Mapped[str] = mapped_column(Text, default="")
    source_url: Mapped[str | None] = mapped_column(String(1024), nullable=True)
    source_title: Mapped[str | None] = mapped_column(String(512), nullable=True)
    bvid: Mapped[str | None] = mapped_column(String(32), nullable=True, index=True)
    cefr: Mapped[str | None] = mapped_column(String(8), nullable=True, index=True)
    accent: Mapped[str | None] = mapped_column(String(32), nullable=True)
    topic: Mapped[str | None] = mapped_column(String(64), nullable=True, index=True)
    duration_sec: Mapped[int | None] = mapped_column(Integer, nullable=True)
    has_subtitles: Mapped[int] = mapped_column(Integer, default=0)
    has_vocab: Mapped[int] = mapped_column(Integer, default=0)
    # public | friends | private
    visibility: Mapped[str] = mapped_column(String(16), default="public", index=True)
    forked_from_id: Mapped[int | None] = mapped_column(
        ForeignKey("community_material_packs.id", ondelete="SET NULL"),
        nullable=True,
        index=True,
    )
    # User opted in to pull upstream updates (default off).
    sync_upstream: Mapped[int] = mapped_column(Integer, default=0)
    fork_count: Mapped[int] = mapped_column(Integer, default=0)
    bookmark_count: Mapped[int] = mapped_column(Integer, default=0)
    meta_json: Mapped[str] = mapped_column(Text, default="{}")
    # visible | hidden | deleted
    status: Mapped[str] = mapped_column(String(16), default="visible", index=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )


class DeskBattle(Base):
    __tablename__ = "desk_battles"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    desk_id: Mapped[int] = mapped_column(Integer, index=True)
    pending_desk_id: Mapped[int | None] = mapped_column(Integer, nullable=True, unique=True)
    sender_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    target_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    status: Mapped[str] = mapped_column(String(16), default="pending")
    result_json: Mapped[str | None] = mapped_column(Text, nullable=True)
    seed: Mapped[str] = mapped_column(String(64))
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


class CommunityFollow(Base):
    __tablename__ = "community_follows"
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), primary_key=True)
    target_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), primary_key=True)


class CommunityBookmark(Base):
    __tablename__ = "community_bookmarks"
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), primary_key=True)
    post_id: Mapped[int] = mapped_column(ForeignKey("community_posts.id", ondelete="CASCADE"), primary_key=True)


class CommunityNotice(Base):
    __tablename__ = "community_notices"
    __table_args__ = (UniqueConstraint("user_id", "event_key", name="uq_community_notice_event"),)
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    actor_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    event_key: Mapped[str] = mapped_column(String(120))
    text: Mapped[str] = mapped_column(String(240))
    post_id: Mapped[int | None] = mapped_column(ForeignKey("community_posts.id", ondelete="CASCADE"), nullable=True)
    read: Mapped[int] = mapped_column(Integer, default=0)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


class CommunityReport(Base):
    __tablename__ = "community_reports"
    __table_args__ = (UniqueConstraint("user_id", "post_id", name="uq_community_report"),)
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    post_id: Mapped[int] = mapped_column(ForeignKey("community_posts.id", ondelete="CASCADE"))
    reason: Mapped[str] = mapped_column(String(500))
    status: Mapped[str] = mapped_column(String(16), default="pending")
    review_note: Mapped[str] = mapped_column(String(500), default="")
    reviewed_by: Mapped[int | None] = mapped_column(ForeignKey("users.id"), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    reviewed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)


class PublicLearningCard(Base):
    __tablename__ = "public_learning_cards"
    token: Mapped[str] = mapped_column(String(48), primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    post_id: Mapped[int] = mapped_column(ForeignKey("community_posts.id", ondelete="CASCADE"))
    active: Mapped[int] = mapped_column(Integer, default=1)
    expression: Mapped[str] = mapped_column(String(240))
    meaning: Mapped[str] = mapped_column(String(500))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


class StudyChallengeMember(Base):
    __tablename__ = "study_challenge_members"
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), primary_key=True)
    challenge_id: Mapped[str] = mapped_column(String(32), primary_key=True)
    joined_day: Mapped[str] = mapped_column(String(10))
    reward_claimed: Mapped[int] = mapped_column(Integer, default=0)
    active: Mapped[int] = mapped_column(Integer, default=1)


class CommunityNoticePreference(Base):
    __tablename__ = "community_notice_preferences"
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), primary_key=True)
    enabled: Mapped[int] = mapped_column(Integer, default=1)


class LearningModuleProgress(Base):
    __tablename__ = 'learning_module_progress'
    user_id: Mapped[int] = mapped_column(ForeignKey('users.id', ondelete='CASCADE'), primary_key=True)
    kind: Mapped[str] = mapped_column(String(16), primary_key=True)
    revision: Mapped[int] = mapped_column(Integer, default=1)
    payload: Mapped[str] = mapped_column(Text)


class OralMatchQueue(Base):
    """Waiting learners for 1:1 peer oral practice / language exchange."""

    __tablename__ = "oral_match_queue"

    user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), primary_key=True
    )
    display_name: Mapped[str] = mapped_column(String(64))
    enqueued_at: Mapped[float] = mapped_column(Float)
    heartbeat_at: Mapped[float] = mapped_column(Float)
    # peer_oral | language_exchange
    mode: Mapped[str] = mapped_column(String(32), default="peer_oral")
    native_lang: Mapped[str] = mapped_column(String(16), default="")
    target_lang: Mapped[str] = mapped_column(String(16), default="")
    topic: Mapped[str] = mapped_column(String(64), default="")
    cefr: Mapped[str] = mapped_column(String(8), default="")
    # video | article | none
    content_kind: Mapped[str] = mapped_column(String(16), default="")
    content_id: Mapped[str] = mapped_column(String(128), default="")
    content_title: Mapped[str] = mapped_column(String(200), default="")
    content_route: Mapped[str] = mapped_column(String(512), default="")


class OralInviteLobby(Base):
    """Open invite room waiting for a peer to accept."""

    __tablename__ = "oral_invite_lobbies"

    id: Mapped[str] = mapped_column(String(24), primary_key=True)
    host_user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    host_name: Mapped[str] = mapped_column(String(64))
    topic: Mapped[str] = mapped_column(String(64), default="")
    content_kind: Mapped[str] = mapped_column(String(16), default="")
    content_id: Mapped[str] = mapped_column(String(128), default="")
    content_title: Mapped[str] = mapped_column(String(200), default="")
    content_route: Mapped[str] = mapped_column(String(512), default="")
    created_at: Mapped[float] = mapped_column(Float)
    heartbeat_at: Mapped[float] = mapped_column(Float)
    closed_at: Mapped[float | None] = mapped_column(Float, nullable=True)


class CommunityStudyGroup(Base):
    """Formal study group with shared weekly material tasks."""

    __tablename__ = "community_study_groups"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    owner_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    title: Mapped[str] = mapped_column(String(120), default="")
    description: Mapped[str] = mapped_column(Text, default="")
    topic: Mapped[str] = mapped_column(String(64), default="")
    cefr: Mapped[str] = mapped_column(String(8), default="")
    visibility: Mapped[str] = mapped_column(String(16), default="public", index=True)
    member_count: Mapped[int] = mapped_column(Integer, default=1)
    status: Mapped[str] = mapped_column(String(16), default="open", index=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )


class CommunityStudyGroupMember(Base):
    __tablename__ = "community_study_group_members"

    group_id: Mapped[int] = mapped_column(
        ForeignKey("community_study_groups.id", ondelete="CASCADE"), primary_key=True
    )
    user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), primary_key=True
    )
    role: Mapped[str] = mapped_column(String(16), default="member")
    joined_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )


class CommunityGroupTask(Base):
    __tablename__ = "community_group_tasks"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    group_id: Mapped[int] = mapped_column(
        ForeignKey("community_study_groups.id", ondelete="CASCADE"), index=True
    )
    week_id: Mapped[str] = mapped_column(String(16), index=True)
    title: Mapped[str] = mapped_column(String(200), default="")
    task_type: Mapped[str] = mapped_column(String(32), default="shadowing")
    material_pack_id: Mapped[int | None] = mapped_column(Integer, nullable=True)
    link_url: Mapped[str | None] = mapped_column(String(1024), nullable=True)
    created_by: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )


class OralPeerRoom(Base):
    """Matched peer oral session (text + optional LiveKit voice)."""

    __tablename__ = "oral_peer_rooms"

    id: Mapped[str] = mapped_column(String(24), primary_key=True)
    user_a: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    name_a: Mapped[str] = mapped_column(String(64))
    user_b: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    name_b: Mapped[str] = mapped_column(String(64))
    created_at: Mapped[float] = mapped_column(Float)
    heartbeat_a: Mapped[float] = mapped_column(Float)
    heartbeat_b: Mapped[float] = mapped_column(Float)
    closed_at: Mapped[float | None] = mapped_column(Float, nullable=True)
    left_by: Mapped[int | None] = mapped_column(Integer, nullable=True)
    topic: Mapped[str] = mapped_column(String(64), default="")
    content_kind: Mapped[str] = mapped_column(String(16), default="")
    content_id: Mapped[str] = mapped_column(String(128), default="")
    content_title: Mapped[str] = mapped_column(String(200), default="")
    content_route: Mapped[str] = mapped_column(String(512), default="")


class OralPeerMessage(Base):
    __tablename__ = "oral_peer_messages"

    id: Mapped[str] = mapped_column(String(16), primary_key=True)
    room_id: Mapped[str] = mapped_column(
        ForeignKey("oral_peer_rooms.id", ondelete="CASCADE"), index=True
    )
    sender_user_id: Mapped[int] = mapped_column(Integer, index=True)
    sender_name: Mapped[str] = mapped_column(String(64))
    text: Mapped[str] = mapped_column(Text)
    created_at: Mapped[float] = mapped_column(Float, index=True)
    # user | system
    kind: Mapped[str] = mapped_column(String(16), default="user")


class OralPeerReport(Base):
    __tablename__ = "oral_peer_reports"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    room_id: Mapped[str] = mapped_column(String(24), index=True)
    reporter_user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    peer_user_id: Mapped[int] = mapped_column(Integer, index=True)
    reason: Mapped[str] = mapped_column(String(500))
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )


class ExamAsset(Base):
    """Community-uploaded exam materials stored on ECS under exam/."""

    __tablename__ = "exam_assets"
    __table_args__ = (
        UniqueConstraint("sha256", "family_id", name="uq_exam_asset_hash_family"),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    family_id: Mapped[str] = mapped_column(String(32), index=True)
    kind: Mapped[str] = mapped_column(String(24), index=True)
    title: Mapped[str] = mapped_column(String(200))
    storage_path: Mapped[str] = mapped_column(String(500))
    sha256: Mapped[str] = mapped_column(String(64), index=True)
    size_bytes: Mapped[int] = mapped_column(Integer, default=0)
    meta_json: Mapped[str] = mapped_column(Text, default="{}")
    # pending | visible | hidden | removed | rejected
    status: Mapped[str] = mapped_column(String(16), default="pending", index=True)
    license_ack: Mapped[int] = mapped_column(Integer, default=0)
    report_count: Mapped[int] = mapped_column(Integer, default=0)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )


class ExamAssetReport(Base):
    __tablename__ = "exam_asset_reports"
    __table_args__ = (
        UniqueConstraint("user_id", "asset_id", name="uq_exam_asset_report"),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    asset_id: Mapped[int] = mapped_column(
        ForeignKey("exam_assets.id", ondelete="CASCADE"), index=True
    )
    reason: Mapped[str] = mapped_column(String(500))
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )


class ApiUsageEvent(Base):
    """Billable LLM/ASR/TTS usage for ops cost + P&L dashboards."""

    __tablename__ = "api_usage_events"
    __table_args__ = (
        UniqueConstraint(
            "user_id",
            "client_event_id",
            name="uq_api_usage_user_client_event",
        ),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    user_id: Mapped[int | None] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL"), nullable=True, index=True
    )
    # Client-side id for idempotent sync from the mobile ledger.
    client_event_id: Mapped[str | None] = mapped_column(String(96), nullable=True, index=True)
    # translation | word_lookup | grammar | asr | tts | writing | other
    kind: Mapped[str] = mapped_column(String(32), default="other", index=True)
    # App / pipeline module for GPU & COGS attribution, e.g. oral_coach | subtitle_asr
    module: Mapped[str] = mapped_column(String(48), default="", index=True)
    # dashscope | deepseek | openai | tencent | ollama | user_key | …
    provider: Mapped[str] = mapped_column(String(32), default="", index=True)
    model: Mapped[str] = mapped_column(String(120), default="")
    # platform | user
    key_owner: Mapped[str] = mapped_column(String(16), default="platform", index=True)
    # Never store raw secrets — sha256[:12] + last4.
    key_fingerprint: Mapped[str] = mapped_column(String(32), default="", index=True)
    key_label: Mapped[str] = mapped_column(String(64), default="")
    prompt_tokens: Mapped[int] = mapped_column(Integer, default=0)
    completion_tokens: Mapped[int] = mapped_column(Integer, default=0)
    audio_seconds: Mapped[float] = mapped_column(Float, default=0.0)
    cost_usd: Mapped[float] = mapped_column(Float, default=0.0)
    cost_cny: Mapped[float] = mapped_column(Float, default=0.0)
    note: Mapped[str] = mapped_column(String(255), default="")
    meta_json: Mapped[str] = mapped_column(Text, default="{}")
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), index=True
    )


# ---------------------------------------------------------------------------
# 素材指纹缓存复用（PRD：一次 GPU 解构，全平台复用）
# UUID 主键便于多节点共享；user_id 仍用现有 users.id（Integer）。
# JSON 字段以 Text 存储，兼容 SQLite / Postgres。
# ---------------------------------------------------------------------------


class AssetCache(Base):
    """公共缓存课程资产包（结构化元数据，不含原始 PDF/MP4）。"""

    __tablename__ = "asset_cache"
    __table_args__ = (
        Index("idx_asset_cache_hit_count", "hit_count"),
        Index("idx_asset_cache_last_hit_at", "last_hit_at"),
        Index("idx_asset_cache_is_ban", "is_ban"),
        Index("idx_asset_cache_ban_hit", "is_ban", "hit_count"),
    )

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    asset_name: Mapped[str] = mapped_column(String(256), default="")
    source_type: Mapped[str] = mapped_column(String(32), default="pdf_text", index=True)
    total_lesson_count: Mapped[int] = mapped_column(Integer, default=0)
    cefr_level: Mapped[str | None] = mapped_column(String(16), nullable=True)
    wordbank_ref_url: Mapped[str | None] = mapped_column(String(512), nullable=True)
    lesson_structure_url: Mapped[str | None] = mapped_column(String(512), nullable=True)
    summary_text: Mapped[str | None] = mapped_column(Text, nullable=True)
    tag_list_json: Mapped[str] = mapped_column(Text, default="[]")
    hit_count: Mapped[int] = mapped_column(BigInteger, default=0)
    last_hit_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    is_ban: Mapped[bool] = mapped_column(Boolean, default=False)
    created_by: Mapped[int | None] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL"), nullable=True, index=True
    )
    create_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
    update_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )


class FingerprintIndex(Base):
    """指纹索引：SimHash 分块 + 外部向量引用。"""

    __tablename__ = "fingerprint_index"
    __table_args__ = (
        Index("idx_fingerprint_asset_id", "asset_id"),
        Index("idx_fingerprint_is_valid", "is_valid"),
        Index(
            "idx_fingerprint_valid_type_len",
            "is_valid",
            "source_type",
            "text_length",
        ),
    )

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    asset_id: Mapped[str] = mapped_column(
        ForeignKey("asset_cache.id", ondelete="CASCADE"), index=True
    )
    source_type: Mapped[str] = mapped_column(String(32), default="pdf_text")
    simhash_blocks_json: Mapped[str] = mapped_column(Text, default="[]")
    vector_ref_id: Mapped[str] = mapped_column(String(128), unique=True, index=True)
    text_length: Mapped[int] = mapped_column(Integer, default=0)
    version_tag: Mapped[str | None] = mapped_column(String(64), nullable=True)
    is_valid: Mapped[bool] = mapped_column(Boolean, default=True)
    create_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
    update_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )


class SimhashBand(Base):
    """SimHash 16 位分带召回表（每指纹 4 行）。"""

    __tablename__ = "simhash_band"
    __table_args__ = (
        Index("idx_simhash_band_value_no", "band_value", "band_no"),
        Index("idx_simhash_band_fp", "fingerprint_id"),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    fingerprint_id: Mapped[str] = mapped_column(
        ForeignKey("fingerprint_index.id", ondelete="CASCADE"), index=True
    )
    asset_id: Mapped[str] = mapped_column(String(36), index=True)
    band_no: Mapped[int] = mapped_column(Integer)  # 0..3
    band_value: Mapped[int] = mapped_column(Integer)
    source_type: Mapped[str] = mapped_column(String(32), default="pdf_text")
    text_length: Mapped[int] = mapped_column(Integer, default=0)


class UserCourseAsset(Base):
    """用户私有课程副本（diff 补丁，不改公共缓存）。"""

    __tablename__ = "user_course_asset"
    __table_args__ = (
        Index("idx_user_course_asset_user_id", "user_id"),
        Index("idx_user_course_asset_cache_id", "asset_cache_id"),
        Index("idx_user_course_user_cache", "user_id", "asset_cache_id"),
    )

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    asset_cache_id: Mapped[str | None] = mapped_column(
        ForeignKey("asset_cache.id", ondelete="SET NULL"), nullable=True
    )
    asset_title: Mapped[str] = mapped_column(String(256), default="")
    diff_patch_json: Mapped[str | None] = mapped_column(Text, nullable=True)
    is_from_cache: Mapped[bool] = mapped_column(Boolean, default=True)
    source_upload_id: Mapped[str | None] = mapped_column(String(36), nullable=True)
    is_shared: Mapped[bool] = mapped_column(Boolean, default=False)
    share_audit_status: Mapped[str] = mapped_column(String(32), default="pending")
    create_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
    update_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )


class UploadTask(Base):
    """用户上传与解析任务状态。"""

    __tablename__ = "upload_task"
    __table_args__ = (
        Index("idx_upload_task_user_id", "user_id"),
        Index("idx_upload_task_status", "status"),
        Index("idx_upload_task_status_time", "status", "create_at"),
    )

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    file_name: Mapped[str | None] = mapped_column(String(256), nullable=True)
    file_type: Mapped[str] = mapped_column(String(32), default="pdf")
    raw_file_key: Mapped[str | None] = mapped_column(String(256), nullable=True)
    # pending / pending_confirm / fingerprint_match / queue_gpu /
    # processing / success / failed
    status: Mapped[str] = mapped_column(String(32), default="pending", index=True)
    fingerprint_id: Mapped[str | None] = mapped_column(String(36), nullable=True)
    user_course_asset_id: Mapped[str | None] = mapped_column(String(36), nullable=True)
    fail_reason: Mapped[str | None] = mapped_column(Text, nullable=True)
    # 1 = success waiting for in-app notify; cleared after client ack.
    notify_pending: Mapped[int] = mapped_column(Integer, default=0)
    create_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
    update_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )


class CacheHitLog(Base):
    """指纹检索命中/未命中埋点。"""

    __tablename__ = "cache_hit_log"
    __table_args__ = (
        Index("idx_cache_hit_log_asset", "asset_cache_id"),
        Index("idx_cache_hit_log_create_at", "create_at"),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    user_id: Mapped[int] = mapped_column(Integer, index=True)
    fingerprint_id: Mapped[str | None] = mapped_column(String(36), nullable=True)
    asset_cache_id: Mapped[str | None] = mapped_column(String(36), nullable=True)
    hit_result: Mapped[str] = mapped_column(String(16), default="miss")  # hit / miss
    cost_ms: Mapped[int] = mapped_column(Integer, default=0)
    create_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), index=True
    )


class ProductFeedback(Base):
    """Private product feedback — admin-only; never listed in community feed."""

    __tablename__ = "product_feedback"
    __table_args__ = (Index("idx_product_feedback_created", "created_at"),)

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    category: Mapped[str] = mapped_column(String(32), default="general", index=True)
    title: Mapped[str] = mapped_column(String(200), default="")
    body: Mapped[str] = mapped_column(Text, default="")
    contact: Mapped[str] = mapped_column(String(120), default="")
    app_version: Mapped[str] = mapped_column(String(64), default="")
    # Optional screenshot URL (ECS /media/… after upload).
    screenshot_url: Mapped[str] = mapped_column(String(512), default="")
    # open | read | done
    status: Mapped[str] = mapped_column(String(16), default="open", index=True)
    admin_note: Mapped[str] = mapped_column(Text, default="")
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), index=True
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )

class UserAuthSession(Base):
    """Active login terminal for an account (max N concurrent devices)."""

    __tablename__ = "user_auth_sessions"
    __table_args__ = (
        UniqueConstraint("user_id", "device_id", name="uq_user_auth_device"),
        Index("idx_user_auth_sessions_user_seen", "user_id", "last_seen_at"),
    )

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    device_id: Mapped[str] = mapped_column(String(128), index=True)
    device_label: Mapped[str] = mapped_column(String(120), default="")
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
    last_seen_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), index=True
    )
    revoked_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True, index=True
    )

class PublishedNetdiskSeries(Base):
    """Licensed netdisk series approved for all authenticated learners."""

    __tablename__ = "published_netdisk_series"
    __table_args__ = (
        UniqueConstraint("slug", name="uq_published_netdisk_slug"),
        UniqueConstraint(
            "publisher_user_id", "series_key", name="uq_published_netdisk_publisher_key"
        ),
        Index("idx_published_netdisk_status", "status"),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    slug: Mapped[str] = mapped_column(String(64), index=True)
    title: Mapped[str] = mapped_column(String(512), default="")
    publisher_user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    series_key: Mapped[str] = mapped_column(String(64), index=True)
    # pending | published | rejected
    status: Mapped[str] = mapped_column(String(16), default="published", index=True)
    license_note: Mapped[str] = mapped_column(Text, default="")
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
    reviewed_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    reviewed_by: Mapped[str | None] = mapped_column(String(120), nullable=True)


class ReadAloudAttempt(Base):
    __tablename__ = "read_aloud_attempts"
    __table_args__ = (Index("ix_read_aloud_user_day", "user_id", "day"),)

    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), primary_key=True)
    attempt_id: Mapped[str] = mapped_column(String(64), primary_key=True)
    day: Mapped[date] = mapped_column(Date)
    duration_ms: Mapped[int] = mapped_column(Integer)
    weak_words: Mapped[list[str]] = mapped_column(JSON)


class CurriculumVocabWord(Base):
    """Global CES2022 appendix-3 whitelist (not user-scoped VocabItem)."""

    __tablename__ = "curriculum_vocab_words"
    __table_args__ = (
        UniqueConstraint("lemma", name="uq_curriculum_vocab_lemma"),
        Index("ix_curriculum_vocab_band", "band"),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    lemma: Mapped[str] = mapped_column(String(120), index=True)
    surface: Mapped[str] = mapped_column(String(160))
    # level2 | level3
    band: Mapped[str] = mapped_column(String(16), default="level2")
    source: Mapped[str] = mapped_column(String(64), default="ces2022_appendix3")
    version: Mapped[str] = mapped_column(String(16), default="2022")
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )


class CurriculumVocabExtend(Base):
    """Optional school/publisher extend pool (phase-1 may be empty)."""

    __tablename__ = "curriculum_vocab_extend"
    __table_args__ = (UniqueConstraint("lemma", name="uq_curriculum_vocab_extend_lemma"),)

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    lemma: Mapped[str] = mapped_column(String(120), index=True)
    surface: Mapped[str] = mapped_column(String(160))
    source: Mapped[str] = mapped_column(String(64), default="extend")
    version: Mapped[str] = mapped_column(String(16), default="2022")
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
