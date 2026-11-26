"""Build multi-lesson CourseOut from UserLinkCourse rows sharing series_key."""

from __future__ import annotations

import hashlib
import re
from pathlib import PurePosixPath
from typing import Any

from app.services.netdisk_play import signed_play_url

_SEASON_NAME_RE = re.compile(r"^(season\s*)?s\d{1,2}$", re.IGNORECASE)
_VERSION_FOLDER_HINTS = (
    "字幕",
    "版本",
    "中英",
    "纯英",
    "无字幕",
    "可切换",
    "1080",
    "720p",
    "2160",
    "bluray",
    "web-dl",
    "webrip",
    "remux",
    "x264",
    "x265",
    "hevc",
)

# Curated shelf titles — prefer these when a path segment matches.
_CURATED_SHOW_TITLES: tuple[tuple[tuple[str, ...], str], ...] = (
    (("绝望的主妇", "绝望主妇", "desperate housewives"), "绝望主妇"),
    (("老友记", "friends", "f.r.i.e.n.d.s"), "老友记"),
    (("摩登家庭", "modern family"), "摩登家庭"),
    (
        (
            "生活大爆炸",
            "big bang theory",
            "the big bang theory",
            "the.big.bang.theory",
            "tbbt",
        ),
        "生活大爆炸",
    ),
    (("哈利·波特", "哈利波特", "harry potter", "harry.potter"), "哈利·波特"),
)


def series_key_for(user_id: int, provider: str, folder_path: str) -> str:
    digest = hashlib.sha1(
        f"{user_id}:{provider}:{folder_path.rstrip('/')}".encode("utf-8")
    ).hexdigest()[:24]
    return f"nd{digest}"


def series_course_id(series_key: str) -> str:
    return f"netdisk-series-{series_key}"


def _looks_like_version_folder(name: str) -> bool:
    lower = name.lower()
    return any(h.lower() in lower for h in _VERSION_FOLDER_HINTS)


def curated_title_from_path(folder_path: str) -> str | None:
    blob = folder_path.lower()
    for aliases, title in _CURATED_SHOW_TITLES:
        for alias in aliases:
            if alias.lower() in blob:
                return title
    return None


def folder_title(folder_path: str, override: str | None = None) -> str:
    if override and override.strip():
        return override.strip()[:512]
    curated = curated_title_from_path(folder_path)
    if curated:
        return curated
    parts = [p for p in PurePosixPath(folder_path.rstrip("/")).parts if p and p != "/"]
    for name in reversed(parts):
        if name.startswith("ae-u"):
            continue
        if _SEASON_NAME_RE.match(name.strip()):
            continue
        if _looks_like_version_folder(name):
            continue
        return name[:512]
    name = PurePosixPath(folder_path.rstrip("/")).name
    return (name or "网盘剧集")[:512]


def to_series_course_out(rows: list[Any], *, series_key: str, series_title: str) -> dict:
    """Emit one CourseOut with N lessons sorted by episode_index."""
    ordered = sorted(
        rows,
        key=lambda r: (
            r.episode_index if r.episode_index is not None else 10_000,
            (r.title or "").lower(),
            r.id,
        ),
    )
    course_id = series_course_id(series_key)
    lessons: list[dict] = []
    provider_tag = "netdisk"
    for i, row in enumerate(ordered, start=1):
        idx = row.episode_index if row.episode_index is not None else i
        has_en = bool(row.subtitle_en_srt)
        has_zh = bool(row.subtitle_zh_srt)
        video_url = signed_play_url(row.id, row.user_id)
        lessons.append(
            {
                "id": f"{course_id}-{idx:02d}",
                "title": row.title,
                "index": idx,
                "durationSec": float(row.duration_sec or 60),
                "videoUrl": video_url,
                "subtitles": {
                    "en": f"/api/imports/{row.id}/srt/en" if has_en else "",
                    "zh": f"/api/imports/{row.id}/srt/zh" if has_zh else None,
                },
            }
        )
        if str(row.source).endswith("_netdisk"):
            provider_tag = str(row.source)
    return {
        "id": course_id,
        "title": series_title,
        "titleZh": series_title,
        "description": f"{series_title} · {len(lessons)} 集 · 网盘导入",
        "coverUrl": None,
        "level": "A2",
        "tags": [provider_tag, "import", "series", "netdisk"],
        "lessons": lessons,
    }
