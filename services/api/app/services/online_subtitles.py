"""Online subtitle lookup for remote netdisk videos.

Providers:
1. Shooter / subfinder four-block fingerprint (HTTP Range, 16 KiB).
2. Subliminal (OpenSubtitles / Podnapisi / Gestdown / …) via filename + optional
   OpenSubtitles movie hash (first+last 64 KiB over Range).

Algorithm/source (Shooter): https://github.com/ausaki/subfinder (MIT, ausaki)
Subliminal: https://github.com/Diaoul/subliminal (MIT)
"""

from __future__ import annotations

import asyncio
import hashlib
import logging
import re
import struct
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import httpx
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import SharedMediaSubtitle
from app.shared_subtitle_quality import evaluate_shared_pack, parse_srt_cues

logger = logging.getLogger(__name__)

SHOOTER_API = "https://www.shooter.cn/api/subapi.php"
_BLOCK_SIZE = 4096
_OS_HASH_BLOCK = 65536

# Curated Chinese shelf titles → English guessit/subliminal search seeds.
_ENGLISH_SEARCH_ALIASES: dict[str, str] = {
    "哈利·波特": "Harry Potter",
    "哈利波特": "Harry Potter",
    "老友记": "Friends",
    "绝望主妇": "Desperate Housewives",
    "绝望的主妇": "Desperate Housewives",
    "摩登家庭": "Modern Family",
    "生活大爆炸": "The Big Bang Theory",
}

# Harry Potter film pack (common netdisk episode_index order).
_HARRY_POTTER_FILMS: dict[int, str] = {
    1: "Harry.Potter.and.the.Philosophers.Stone.2001",
    2: "Harry.Potter.and.the.Chamber.of.Secrets.2002",
    3: "Harry.Potter.and.the.Prisoner.of.Azkaban.2004",
    4: "Harry.Potter.and.the.Goblet.of.Fire.2005",
    5: "Harry.Potter.and.the.Order.of.the.Phoenix.2007",
    6: "Harry.Potter.and.the.Half-Blood.Prince.2009",
    7: "Harry.Potter.and.the.Deathly.Hallows.Part.1.2010",
    8: "Harry.Potter.and.the.Deathly.Hallows.Part.2.2011",
}

_DEFAULT_SUBLIMINAL_PROVIDERS = (
    "opensubtitles",
    "podnapisi",
    "gestdown",
    "tvsubtitles",
)


@dataclass(frozen=True)
class OnlineSubtitleMatch:
    file_hash: str
    language: str
    srt: str
    source_ref: str
    source_origin: str = "subfinder"


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


def _opensubtitles_hash_from_parts(
    file_size: int, head: bytes, tail: bytes
) -> str:
    if file_size < _OS_HASH_BLOCK * 2:
        raise ValueError("media file is too small for OpenSubtitles hash")
    if len(head) != _OS_HASH_BLOCK or len(tail) != _OS_HASH_BLOCK:
        raise ValueError("OpenSubtitles hash blocks must be 64 KiB")
    filehash = file_size
    for chunk in (head, tail):
        for i in range(0, _OS_HASH_BLOCK, 8):
            (value,) = struct.unpack_from("<q", chunk, i)
            filehash = (filehash + value) & 0xFFFFFFFFFFFFFFFF
    return f"{filehash:016x}"


async def compute_opensubtitles_hash(
    raw_url: str,
    file_size: int,
    *,
    client: httpx.AsyncClient | None = None,
) -> str:
    """OpenSubtitles movie hash over HTTP Range (first + last 64 KiB)."""
    owns_client = client is None
    http = client or httpx.AsyncClient(follow_redirects=True, timeout=20)
    try:
        head = await _read_range(http, raw_url, 0, _OS_HASH_BLOCK)
        tail = await _read_range(
            http, raw_url, max(0, file_size - _OS_HASH_BLOCK), _OS_HASH_BLOCK
        )
    finally:
        if owns_client:
            await http.aclose()
    return _opensubtitles_hash_from_parts(file_size, head, tail)


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
    """Search/download exact fingerprint matches through Shooter/subfinder."""
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
                        OnlineSubtitleMatch(
                            file_hash,
                            language,
                            srt,
                            link,
                            source_origin="shooter",
                        )
                    )
                    break
                if any(m.language == language for m in matches):
                    break
    return matches


def _ascii_slug(text: str) -> str:
    cleaned = re.sub(r"[^\w\s.\-]+", " ", text, flags=re.UNICODE)
    cleaned = re.sub(r"\s+", ".", cleaned.strip())
    return cleaned.strip(".")


def _english_alias(title: str | None) -> str | None:
    raw = (title or "").strip()
    if not raw:
        return None
    if raw in _ENGLISH_SEARCH_ALIASES:
        return _ENGLISH_SEARCH_ALIASES[raw]
    lower = raw.lower()
    for zh, en in _ENGLISH_SEARCH_ALIASES.items():
        if zh.lower() in lower or en.lower() in lower:
            return en
    if re.search(r"[A-Za-z]", raw):
        return raw
    return None


def subliminal_candidate_names(
    filename: str,
    *,
    series_title: str | None = None,
    episode_index: int | None = None,
) -> list[str]:
    """Build guessit-friendly filenames for Subliminal (EN release style)."""
    base = Path(filename or "video.mkv").name
    stem = Path(base).stem
    ext = Path(base).suffix or ".mkv"
    names: list[str] = []

    def _add(name: str) -> None:
        candidate = name if name.lower().endswith((".mkv", ".mp4", ".avi", ".m4v")) else f"{name}{ext}"
        if candidate not in names:
            names.append(candidate)

    _add(base)
    slug = _ascii_slug(stem)
    if slug and slug != stem:
        _add(f"{slug}{ext}")

    alias = _english_alias(series_title) or _english_alias(stem)
    if alias:
        alias_slug = _ascii_slug(alias)
        if alias.lower() == "harry potter" and episode_index in _HARRY_POTTER_FILMS:
            _add(f"{_HARRY_POTTER_FILMS[episode_index]}.1080p.BluRay.x264{ext}")
        if episode_index is not None and episode_index > 0:
            # TV-style: Show.Name.S01E02 / Show.Name.E02
            _add(f"{alias_slug}.S01E{episode_index:02d}{ext}")
            _add(f"{alias_slug}.E{episode_index:02d}{ext}")
        _add(f"{alias_slug}{ext}")

    return names


def _subliminal_provider_configs() -> dict[str, dict[str, Any]]:
    try:
        from app.config import settings
    except Exception:  # pragma: no cover
        return {}

    configs: dict[str, dict[str, Any]] = {}
    os_user = (settings.opensubtitles_username or "").strip()
    os_pass = (settings.opensubtitles_password or "").strip()
    if os_user and os_pass:
        configs["opensubtitles"] = {"username": os_user, "password": os_pass}
        configs["opensubtitlesvip"] = {"username": os_user, "password": os_pass}

    osc_user = (settings.opensubtitlescom_username or "").strip()
    osc_pass = (settings.opensubtitlescom_password or "").strip()
    osc_key = (settings.opensubtitlescom_apikey or "").strip()
    if osc_user and osc_pass:
        entry: dict[str, Any] = {"username": osc_user, "password": osc_pass}
        if osc_key:
            entry["apikey"] = osc_key
        configs["opensubtitlescom"] = entry
        configs["opensubtitlescomvip"] = entry
    return configs


def _subliminal_providers() -> list[str]:
    try:
        from app.config import settings

        raw = (settings.subliminal_providers or "").strip()
    except Exception:  # pragma: no cover
        raw = ""
    providers = [p.strip() for p in raw.split(",") if p.strip()]
    if not providers:
        providers = list(_DEFAULT_SUBLIMINAL_PROVIDERS)
    # Enable opensubtitlescom only when credentials exist.
    configs = _subliminal_provider_configs()
    if "opensubtitlescom" in configs and "opensubtitlescom" not in providers:
        providers.append("opensubtitlescom")
    return providers


def _search_subliminal_sync(
    *,
    filenames: list[str],
    file_size: int | None,
    opensubtitles_hash: str | None,
    languages: tuple[str, ...],
) -> list[OnlineSubtitleMatch]:
    from babelfish import Language
    from subliminal import Video, download_best_subtitles

    lang_set = set()
    for code in languages:
        try:
            lang_set.add(Language.fromietf(code))
        except Exception:
            continue
    if not lang_set:
        lang_set = {Language("eng")}

    providers = _subliminal_providers()
    provider_configs = _subliminal_provider_configs()
    matches: list[OnlineSubtitleMatch] = []
    wanted = set(languages)

    for name in filenames:
        try:
            video = Video.fromname(name)
        except Exception:
            continue
        if file_size and file_size > 0:
            video.size = int(file_size)
        if opensubtitles_hash:
            video.hashes.update(
                {
                    "opensubtitles": opensubtitles_hash,
                    "opensubtitlesvip": opensubtitles_hash,
                    "opensubtitlescom": opensubtitles_hash,
                    "opensubtitlescomvip": opensubtitles_hash,
                }
            )
        try:
            best = download_best_subtitles(
                {video},
                lang_set,
                providers=providers,
                provider_configs=provider_configs or None,
                only_one=False,
                min_score=0,
            )
        except Exception as exc:  # noqa: BLE001
            logger.info("subliminal search failed for %s: %s", name, exc)
            continue
        for sub in best.get(video) or []:
            if not sub.content:
                continue
            text = (sub.text or "").strip()
            if len(parse_srt_cues(text)) < 5:
                continue
            alpha2 = str(sub.language.alpha2) if sub.language else "en"
            if alpha2 not in wanted and "en" in wanted and alpha2.startswith("en"):
                alpha2 = "en"
            if alpha2 not in wanted:
                # Map common OpenSubtitles codes.
                if alpha2 in {"eng"} and "en" in wanted:
                    alpha2 = "en"
                elif alpha2 in {"zho", "chi", "zh"} and "zh" in wanted:
                    alpha2 = "zh"
                else:
                    continue
            if any(m.language == alpha2 for m in matches):
                continue
            ref = f"subliminal:{sub.provider_name}:{getattr(sub, 'id', '')}"
            matches.append(
                OnlineSubtitleMatch(
                    file_hash=opensubtitles_hash or f"name:{name}",
                    language=alpha2,
                    srt=text,
                    source_ref=ref[:1024],
                    source_origin="subliminal",
                )
            )
        if any(m.language == "en" for m in matches):
            break
    return matches


async def search_subliminal(
    *,
    filename: str,
    file_size: int | None = None,
    raw_url: str | None = None,
    languages: tuple[str, ...] = ("en",),
    series_title: str | None = None,
    episode_index: int | None = None,
    client: httpx.AsyncClient | None = None,
) -> list[OnlineSubtitleMatch]:
    """Search Subliminal providers by release name (+ optional OS hash)."""
    try:
        from app.config import settings

        if not bool(getattr(settings, "subliminal_enabled", True)):
            return []
    except Exception:
        pass

    opensubtitles_hash: str | None = None
    if raw_url and file_size and file_size >= _OS_HASH_BLOCK * 2:
        try:
            opensubtitles_hash = await compute_opensubtitles_hash(
                raw_url, int(file_size), client=client
            )
        except Exception as exc:  # noqa: BLE001
            logger.debug("opensubtitles hash skipped: %s", exc)

    candidates = subliminal_candidate_names(
        filename, series_title=series_title, episode_index=episode_index
    )
    return await asyncio.to_thread(
        _search_subliminal_sync,
        filenames=candidates,
        file_size=file_size,
        opensubtitles_hash=opensubtitles_hash,
        languages=languages,
    )


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


async def fetch_and_cache_english_subtitle(
    db: AsyncSession,
    *,
    raw_url: str,
    file_size: int,
    filename: str,
    title: str,
    uploader_user_id: int | None = None,
    series_title: str | None = None,
    episode_index: int | None = None,
) -> str | None:
    """Shooter fingerprint first, then Subliminal name/hash search; cache hits."""
    file_hash: str | None = None
    async with httpx.AsyncClient(follow_redirects=True, timeout=25) as client:
        try:
            file_hash = await compute_subfinder_hash(
                raw_url, file_size, client=client
            )
        except Exception as exc:  # noqa: BLE001
            logger.debug("shooter hash skipped: %s", exc)

        if file_hash:
            cached = await get_shared_media_subtitle(
                db, file_hash=file_hash, language="en"
            )
            if cached is not None:
                cached.hit_count = int(cached.hit_count or 0) + 1
                return cached.subtitle_srt

            try:
                matches = await search_shooter(
                    file_hash=file_hash,
                    filename=filename,
                    languages=("en",),
                )
            except Exception as exc:  # noqa: BLE001
                logger.info("shooter search failed: %s", exc)
                matches = []
            if matches:
                match = matches[0]
                row = await store_shared_media_subtitle(
                    db,
                    file_hash=file_hash,
                    file_size=file_size,
                    duration_sec=None,
                    title=title,
                    language="en",
                    subtitle_srt=match.srt,
                    source_ref=match.source_ref,
                    source_origin=match.source_origin,
                    uploader_user_id=uploader_user_id,
                    episode=episode_index,
                )
                return row.subtitle_srt

        try:
            matches = await search_subliminal(
                filename=filename,
                file_size=file_size,
                raw_url=raw_url,
                languages=("en",),
                series_title=series_title,
                episode_index=episode_index,
                client=client,
            )
        except Exception as exc:  # noqa: BLE001
            logger.info("subliminal search failed: %s", exc)
            matches = []
        if not matches:
            return None
        match = matches[0]
        cache_hash = file_hash or match.file_hash
        try:
            row = await store_shared_media_subtitle(
                db,
                file_hash=cache_hash,
                file_size=file_size,
                duration_sec=None,
                title=title,
                language="en",
                subtitle_srt=match.srt,
                source_ref=match.source_ref,
                source_origin=match.source_origin,
                uploader_user_id=uploader_user_id,
                episode=episode_index,
            )
            return row.subtitle_srt
        except Exception:
            return match.srt
