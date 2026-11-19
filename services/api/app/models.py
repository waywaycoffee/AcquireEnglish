from datetime import datetime

from sqlalchemy import DateTime, Float, ForeignKey, Integer, String, Text, UniqueConstraint, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base


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
    wechat_unionid: Mapped[str | None] = mapped_column(
        String(64), unique=True, index=True, nullable=True
    )
    points_balance: Mapped[int] = mapped_column(Integer, default=0)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())

    progresses: Mapped[list["LessonProgress"]] = relationship(back_populates="user")
    vocab_items: Mapped[list["VocabItem"]] = relationship(back_populates="user")
    phrase_items: Mapped[list["PhraseItem"]] = relationship(back_populates="user")
    preference: Mapped["UserPreference | None"] = relationship(
        back_populates="user", uselist=False
    )
    link_courses: Mapped[list["UserLinkCourse"]] = relationship(back_populates="user")
    entitlements: Mapped[list["UserEntitlement"]] = relationship(back_populates="user")
    orders: Mapped[list["Order"]] = relationship(back_populates="user")
    wallet: Mapped["WalletAccount | None"] = relationship(
        back_populates="user", uselist=False
    )
    points_ledger: Mapped[list["UserPointsLedger"]] = relationship(back_populates="user")


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
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )

    user: Mapped[User] = relationship(back_populates="preference")


class SharedBilibiliSubtitle(Base):
    """Community cache of filled EN/ZH softsubs keyed by Bilibili episode."""

    __tablename__ = "shared_bilibili_subtitles"
    __table_args__ = (
        UniqueConstraint("bvid", "page", name="uq_shared_bili_bvid_page"),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    bvid: Mapped[str] = mapped_column(String(32), index=True)
    page: Mapped[int] = mapped_column(Integer, default=1)
    cid: Mapped[int | None] = mapped_column(Integer, nullable=True, index=True)
    duration_sec: Mapped[int | None] = mapped_column(Integer, nullable=True)
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
