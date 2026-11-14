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
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())

    progresses: Mapped[list["LessonProgress"]] = relationship(back_populates="user")
    vocab_items: Mapped[list["VocabItem"]] = relationship(back_populates="user")
    preference: Mapped["UserPreference | None"] = relationship(
        back_populates="user", uselist=False
    )
    link_courses: Mapped[list["UserLinkCourse"]] = relationship(back_populates="user")


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
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())

    user: Mapped[User] = relationship(back_populates="link_courses")
