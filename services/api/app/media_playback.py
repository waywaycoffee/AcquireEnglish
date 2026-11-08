"""Resolve and cache seekable study media for imported link lessons.

Bilibili/YouTube watch pages are not playable in <video>/media_kit. For Web study
we cache a browser-playable audio track (m4a/mp3) under media/imports/{id}/ so
currentTime-driven subtitle sync works. Upstream watch URLs never leave the DB —
callers cannot pass arbitrary proxy targets (no open proxy).
"""

from __future__ import annotations

import logging
from dataclasses import dataclass
from pathlib import Path

import httpx

from app.audio_extract import FFMPEG_BIN, _run
from app.config import settings
from app.link_import import _BV, _YT_ID, _bilibili_headers

logger = logging.getLogger(__name__)


@dataclass
class PlaybackInfo:
    ready: bool
    mime: str
    kind: str  # "audio" | "video"
    path: Path | None = None
    detail: str | None = None


def media_cache_root() -> Path:
    root = Path(settings.media_cache_dir).expanduser()
    root.mkdir(parents=True, exist_ok=True)
    return root


def import_media_dir(import_id: int) -> Path:
    d = media_cache_root() / "imports" / str(import_id)
    d.mkdir(parents=True, exist_ok=True)
    return d


def cached_study_audio(import_id: int) -> Path | None:
    d = import_media_dir(import_id)
    for name in ("study.m4a", "study.mp3", "study.mp4"):
        p = d / name
        if p.is_file() and p.stat().st_size > 1024:
            return p
    return None


def mime_for_path(path: Path) -> str:
    suffix = path.suffix.lower()
    if suffix == ".mp3":
        return "audio/mpeg"
    if suffix == ".mp4":
        return "video/mp4"
    return "audio/mp4"


async def ensure_study_media(
    import_id: int,
    watch_url: str,
    *,
    bilibili_cookie: str | None = None,
    max_seconds: int = 3 * 60 * 60,
) -> PlaybackInfo:
    """Return cached seekable media, downloading once if needed."""
    existing = cached_study_audio(import_id)
    if existing is not None:
        kind = "video" if existing.suffix.lower() == ".mp4" else "audio"
        return PlaybackInfo(ready=True, mime=mime_for_path(existing), kind=kind, path=existing)

    dest_dir = import_media_dir(import_id)
    try:
        if _BV.search(watch_url) or "bilibili.com" in watch_url:
            out = await _cache_bilibili_audio(
                watch_url,
                dest_dir / "study.m4a",
                cookie=bilibili_cookie,
                max_seconds=max_seconds,
            )
        elif _YT_ID.search(watch_url) or "youtu" in watch_url:
            out = _cache_ytdlp_audio(watch_url, dest_dir / "study.mp3", max_seconds=max_seconds)
        elif watch_url.startswith("http"):
            out = await _cache_http_media(watch_url, dest_dir / "study.m4a", max_seconds=max_seconds)
        else:
            return PlaybackInfo(
                ready=False,
                mime="",
                kind="audio",
                detail="不支持的媒体链接",
            )
    except Exception as exc:
        logger.exception("ensure_study_media failed import_id=%s", import_id)
        return PlaybackInfo(ready=False, mime="", kind="audio", detail=str(exc)[-300:])

    kind = "video" if out.suffix.lower() == ".mp4" else "audio"
    return PlaybackInfo(ready=True, mime=mime_for_path(out), kind=kind, path=out)


async def resolve_bilibili_stream(
    watch_url: str,
    *,
    cookie: str | None = None,
    prefer: str = "audio",
) -> tuple[str, dict[str, str]]:
    """Return (stream_url, download_headers) for App / tooling. prefer: audio|video|durl."""
    m = _BV.search(watch_url)
    if not m:
        raise ValueError("无效的 Bilibili 链接")
    bvid = m.group(1)
    headers = _bilibili_headers(cookie)
    async with httpx.AsyncClient(headers=headers, timeout=60.0, follow_redirects=True) as client:
        view = await client.get(
            "https://api.bilibili.com/x/web-interface/view",
            params={"bvid": bvid},
        )
        view.raise_for_status()
        root = view.json()
        if root.get("code") != 0:
            raise ValueError(root.get("message") or "无法获取 B 站视频信息")
        data = root.get("data") or {}
        pages = data.get("pages") or []
        cid = data.get("cid") or (pages[0].get("cid") if pages else None)
        if not cid:
            raise ValueError("缺少 cid")

        # Prefer legacy combined stream when available (flv/mp4 with A+V).
        if prefer == "durl":
            play = await client.get(
                "https://api.bilibili.com/x/player/playurl",
                params={"bvid": bvid, "cid": cid, "qn": 64, "fnval": 0},
            )
            play.raise_for_status()
            play_root = play.json()
            if play_root.get("code") == 0:
                durl = ((play_root.get("data") or {}).get("durl") or [])
                if durl and durl[0].get("url"):
                    return str(durl[0]["url"]), _cdn_headers(cookie)

        play = await client.get(
            "https://api.bilibili.com/x/player/playurl",
            params={"bvid": bvid, "cid": cid, "fnval": 16, "fourk": 1},
        )
        play.raise_for_status()
        play_root = play.json()
        if play_root.get("code") != 0:
            raise ValueError(play_root.get("message") or "无法获取播放地址")
        dash = ((play_root.get("data") or {}).get("dash") or {})
        if prefer == "video":
            videos = dash.get("video") or []
            if not videos:
                raise ValueError("该视频没有可下载的视频流")
            videos = sorted(videos, key=lambda a: int(a.get("bandwidth") or 0))
            picked = videos[len(videos) // 2]
            url = picked.get("baseUrl") or picked.get("base_url")
        else:
            audios = dash.get("audio") or []
            if not audios:
                raise ValueError("该视频没有可下载的音频流")
            audios = sorted(audios, key=lambda a: int(a.get("bandwidth") or 0))
            picked = audios[len(audios) // 2]
            url = picked.get("baseUrl") or picked.get("base_url")
        if not url:
            raise ValueError("播放地址为空")
        return str(url), _cdn_headers(cookie)


def _cdn_headers(cookie: str | None) -> dict[str, str]:
    headers = {
        "User-Agent": (
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
            "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"
        ),
        "Referer": "https://www.bilibili.com",
        "Accept": "*/*",
    }
    if cookie:
        headers["Cookie"] = cookie.strip()
    return headers


async def _cache_bilibili_audio(
    watch_url: str,
    out: Path,
    *,
    cookie: str | None,
    max_seconds: int,
) -> Path:
    audio_url, dl_headers = await resolve_bilibili_stream(
        watch_url, cookie=cookie, prefer="audio"
    )
    raw = out.with_suffix(".raw.m4a")
    async with httpx.AsyncClient(timeout=180.0, follow_redirects=True) as dl:
        async with dl.stream("GET", audio_url, headers=dl_headers) as resp:
            resp.raise_for_status()
            with raw.open("wb") as f:
                async for chunk in resp.aiter_bytes():
                    f.write(chunk)
    _ffmpeg_to_seekable_audio(raw, out, max_seconds=max_seconds)
    raw.unlink(missing_ok=True)
    return out


def _cache_ytdlp_audio(watch_url: str, out: Path, *, max_seconds: int) -> Path:
    section = f"*0-{max_seconds}"
    target = out.parent / "ytdlp_study.%(ext)s"
    try:
        _run(
            [
                "yt-dlp",
                "-x",
                "--audio-format",
                "mp3",
                "--download-sections",
                section,
                "-o",
                str(target),
                watch_url,
            ]
        )
    except FileNotFoundError as exc:
        raise ValueError("服务器未安装 yt-dlp，暂无法处理 YouTube 精听音轨") from exc
    produced = out.parent / "ytdlp_study.mp3"
    if not produced.exists():
        matches = list(out.parent.glob("ytdlp_study.*"))
        if not matches:
            raise RuntimeError("yt-dlp 未生成音轨")
        produced = matches[0]
    if produced != out:
        produced.replace(out)
    return out


async def _cache_http_media(url: str, out: Path, *, max_seconds: int) -> Path:
    raw = out.with_suffix(".bin")
    async with httpx.AsyncClient(timeout=180.0, follow_redirects=True) as client:
        async with client.stream("GET", url) as resp:
            resp.raise_for_status()
            with raw.open("wb") as f:
                async for chunk in resp.aiter_bytes():
                    f.write(chunk)
    _ffmpeg_to_seekable_audio(raw, out, max_seconds=max_seconds)
    raw.unlink(missing_ok=True)
    return out


def _ffmpeg_to_seekable_audio(src: Path, dest: Path, *, max_seconds: int) -> None:
    """Normalize to AAC-in-M4A (or MP3) so browsers can seek via Range."""
    dest.parent.mkdir(parents=True, exist_ok=True)
    if dest.suffix.lower() == ".mp3":
        _run(
            [
                FFMPEG_BIN,
                "-y",
                "-i",
                str(src),
                "-t",
                str(max_seconds),
                "-vn",
                "-ac",
                "1",
                "-ar",
                "44100",
                "-b:a",
                "96k",
                str(dest),
            ]
        )
        return
    _run(
        [
            FFMPEG_BIN,
            "-y",
            "-i",
            str(src),
            "-t",
            str(max_seconds),
            "-vn",
            "-c:a",
            "aac",
            "-b:a",
            "96k",
            "-movflags",
            "+faststart",
            str(dest),
        ]
    )
