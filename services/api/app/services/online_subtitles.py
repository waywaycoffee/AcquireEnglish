"""Online subtitle lookup compatible with ausaki/subfinder.

The upstream MIT project expects a complete local video file.  Netdisk videos
are remote, so we apply its Shooter four-block fingerprint over HTTP Range
requests instead.  This transfers only 16 KiB per lookup.

Algorithm/source: https://github.com/ausaki/subfinder (MIT, ausaki).
"""

from __future__ import annotations

import hashlib
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import httpx
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import SharedMediaSubtitle
from app.shared_subtitle_quality import evaluate_shared_pack, parse_srt_cues

SHOOTER_API = "https://www.shooter.cn/api/subapi.php"
_BLOCK_SIZE = 4096


@dataclass(frozen=True)
class OnlineSubtitleMatch:
    file_hash: str
    language: str
    srt: str
    source_ref: str


async def _read_range(
    client: httpx.AsyncClient, url: str, start: int, length: int = _BLOCK_SIZE
) -> bytes:
    headers = {"Range": f"bytes={start}-{start + length - 1}"}
    async with client.stream("GET", url, headers=headers) as response:
        response.raise_for_status()
        if response.status_code != 206:
            raise ValueError("upstream ignored byte range")
        body = bytearray()
        async for chunk in response.aiter_bytes():
            body.extend(chunk)
            if len(body) > length:
                raise ValueError("upstream returned an oversized byte range")
    if len(body) != length:
        raise ValueError(f"short byte range: {len(body)}/{length}")
    return bytes(body)


async def compute_subfinder_hash(
    raw_url: str,
    file_size: int,
    *,
    client: httpx.AsyncClient | None = None,
) -> str:
    """Compute subfinder/Shooter's four MD5 media fingerprint remotely."""
    if file_size < _BLOCK_SIZE + 8192:
        raise ValueError("media file is too small")
    positions = [4096, file_size // 3 * 2, file_size // 3, file_size - 8192]
    owns_client = client is None
    http = client or httpx.AsyncClient(follow_redirects=True, timeout=20)
    try:
        blocks = [await _read_range(http, raw_url, pos) for pos in positions]
    finally:
        if owns_client:
            await http.aclose()
    return ";".join(hashlib.md5(block).hexdigest() for block in blocks)


def _decode_subtitle(data: bytes) -> str:
    for encoding in ("utf-8-sig", "utf-16", "gb18030", "big5"):
        try:
            return data.decode(encoding)
        except (UnicodeDecodeError, LookupError):
            continue
    return data.decode("utf-8", errors="replace")


async def search_shooter(
    *,
    file_hash: str,
    filename: str,
    languages: tuple[str, ...] = ("en", "zh"),
) -> list[OnlineSubtitleMatch]:
    """Search/download exact fingerprint matches through subfinder's source."""
    language_map = {"en": "Eng", "zh": "Chn"}
    matches: list[OnlineSubtitleMatch] = []
    async with httpx.AsyncClient(follow_redirects=True, timeout=20) as client:
        for language in languages:
            response = await client.post(
                SHOOTER_API,
                data={
                    "filehash": file_hash,
                    "pathinfo": Path(filename).name,
                    "format": "json",
                    "lang": language_map[language],
                },
            )
            response.raise_for_status()
            try:
                groups: list[dict[str, Any]] = response.json()
            except Exception:  # Shooter returns a one-byte sentinel on misses.
                continue
            for group in groups or []:
                for item in group.get("Files") or []:
                    ext = str(item.get("Ext") or "").lower()
                    link = str(item.get("Link") or "").strip()
                    if ext != "srt" or not link:
                        continue
                    downloaded = await client.get(link)
                    downloaded.raise_for_status()
                    srt = _decode_subtitle(downloaded.content).strip()
                    if len(parse_srt_cues(srt)) < 5:
                        continue
                    matches.append(
                        OnlineSubtitleMatch(file_hash, language, srt, link)
                    )
                    break
                if any(m.language == language for m in matches):
                    break
    return matches


async def get_shared_media_subtitle(
    db: AsyncSession, *, file_hash: str, language: str
) -> SharedMediaSubtitle | None:
    return await db.scalar(
        select(SharedMediaSubtitle).where(
            SharedMediaSubtitle.file_hash == file_hash,
            SharedMediaSubtitle.language == language,
        )
    )


async def store_shared_media_subtitle(
    db: AsyncSession,
    *,
    file_hash: str,
    file_size: int | None,
    duration_sec: int | None,
    title: str,
    language: str,
    subtitle_srt: str,
    source_ref: str,
    source_origin: str = "subfinder",
    uploader_user_id: int | None = None,
    season: int | None = None,
    episode: int | None = None,
) -> SharedMediaSubtitle:
    srt = (subtitle_srt or "").strip()
    quality = evaluate_shared_pack(
        en_srt=srt if language == "en" else srt,
        duration_sec=duration_sec,
    )
    if not quality.passed:
        # Third-party timelines can omit credits; retain structural checks while
        # avoiding a false rejection from approximate duration metadata.
        quality = evaluate_shared_pack(en_srt=srt, duration_sec=None)
    if not quality.passed:
        raise ValueError(quality.reason or "subtitle quality check failed")
    row = await get_shared_media_subtitle(
        db, file_hash=file_hash, language=language
    )
    if row is None:
        row = SharedMediaSubtitle(file_hash=file_hash, language=language, subtitle_srt=srt)
        db.add(row)
    elif float(row.quality_score or 0) > quality.score:
        return row
    row.file_size = file_size
    row.duration_sec = duration_sec
    row.title = (title or "")[:512]
    row.season = season
    row.episode = episode
    row.subtitle_srt = srt
    row.cue_count = quality.cue_count
    row.quality_score = quality.score
    row.source_origin = (source_origin or "subfinder")[:32]
    row.source_ref = (source_ref or "")[:1024]
    row.uploader_user_id = uploader_user_id
    await db.flush()
    return row
