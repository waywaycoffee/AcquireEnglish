"""Extract text softsubtitle tracks embedded in MKV/MP4 (not burned-in hardsubs)."""
from __future__ import annotations

import asyncio
import json
import shutil
import subprocess
import tempfile
from pathlib import Path
from typing import Any, Literal

from app.link_import import _srt_looks_chinese
from app.services.netdisk_sidecars import normalize_subtitle_text
from app.services.openlist_client import OpenListClient, OpenListError, public_raw_url

Lang = Literal["en", "zh"]

_CONTAINER_SUFFIXES = (".mkv", ".mp4", ".m4v", ".mov", ".webm")
_TEXT_CODECS = {
    "subrip",
    "srt",
    "ass",
    "ssa",
    "mov_text",
    "text",
    "webvtt",
    "ttml",
    "timed_id3",
}
_BITMAP_CODECS = {
    "hdmv_pgs_subtitle",
    "dvd_subtitle",
    "dvd_nav_packet",
    "dvb_subtitle",
    "xsub",
    "pgssub",
}

_EN_LANG = {"en", "eng", "english", "en-us", "en_us", "en-gb", "en_gb"}
_ZH_LANG = {
    "zh",
    "zho",
    "chi",
    "zh-cn",
    "zh_cn",
    "zh-hans",
    "zh_hans",
    "zh-tw",
    "zh_tw",
    "zh-hant",
    "chs",
    "cht",
    "chinese",
    "cn",
}


def _ffmpeg_bin() -> str:
    for cand in ("/usr/bin/ffmpeg", "/usr/local/bin/ffmpeg", "ffmpeg"):
        if cand == "ffmpeg" or Path(cand).exists():
            return cand
    return "ffmpeg"


def _ffprobe_bin() -> str:
    for cand in ("/usr/bin/ffprobe", "/usr/local/bin/ffprobe", "ffprobe"):
        if cand == "ffprobe" or Path(cand).exists():
            return cand
    return "ffprobe"


def supports_embedded_softsubs(path: str) -> bool:
    lower = path.lower()
    return any(lower.endswith(suf) for suf in _CONTAINER_SUFFIXES)


def _tag_lang(tags: dict[str, Any] | None) -> Lang | None:
    if not isinstance(tags, dict):
        return None
    raw = str(tags.get("language") or tags.get("LANGUAGE") or "").strip().lower()
    packed = raw.replace("_", "-")
    head = packed.split("-", 1)[0] if packed else ""
    for cand in (packed, head, raw):
        if cand in _EN_LANG:
            return "en"
        if cand in _ZH_LANG:
            return "zh"
    title = str(tags.get("title") or tags.get("TITLE") or "").lower()
    if any(t in title for t in ("english", "eng", "英文")):
        return "en"
    if any(t in title for t in ("chinese", "简体", "繁体", "中文", "chs", "cht")):
        return "zh"
    return None


def _sniff_lang(srt: str) -> Lang:
    return "zh" if _srt_looks_chinese(srt) else "en"


def _run(cmd: list[str], *, timeout: float) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        cmd,
        capture_output=True,
        text=True,
        timeout=timeout,
        check=False,
    )


def _probe_subtitle_streams(url: str, *, timeout: float = 45.0) -> list[dict[str, Any]]:
    cmd = [
        _ffprobe_bin(),
        "-v",
        "error",
        "-user_agent",
        "pan.baidu.com",
        "-print_format",
        "json",
        "-show_streams",
        "-select_streams",
        "s",
        "-i",
        url,
    ]
    proc = _run(cmd, timeout=timeout)
    if proc.returncode != 0:
        return []
    try:
        payload = json.loads(proc.stdout or "{}")
    except json.JSONDecodeError:
        return []
    streams = payload.get("streams")
    return streams if isinstance(streams, list) else []


def _extract_stream_to_srt(
    url: str,
    *,
    stream_index: int,
    out_path: Path,
    timeout: float = 90.0,
) -> str | None:
    """Map absolute stream index → UTF-8 SRT text via ffmpeg."""
    cmd = [
        _ffmpeg_bin(),
        "-nostdin",
        "-hide_banner",
        "-loglevel",
        "error",
        "-y",
        "-user_agent",
        "pan.baidu.com",
        "-i",
        url,
        "-map",
        f"0:{stream_index}",
        "-c:s",
        "srt",
        str(out_path),
    ]
    proc = _run(cmd, timeout=timeout)
    if proc.returncode != 0 or not out_path.is_file() or out_path.stat().st_size < 8:
        # ASS-heavy tracks sometimes need codec copy then normalize.
        ass_path = out_path.with_suffix(".ass")
        cmd_ass = [
            _ffmpeg_bin(),
            "-nostdin",
            "-hide_banner",
            "-loglevel",
            "error",
            "-y",
            "-user_agent",
            "pan.baidu.com",
            "-i",
            url,
            "-map",
            f"0:{stream_index}",
            "-c:s",
            "copy",
            str(ass_path),
        ]
        proc2 = _run(cmd_ass, timeout=timeout)
        if proc2.returncode != 0 or not ass_path.is_file():
            return None
        raw = ass_path.read_text(encoding="utf-8", errors="replace")
        return normalize_subtitle_text(ass_path.name, raw)
    raw = out_path.read_text(encoding="utf-8", errors="replace")
    return normalize_subtitle_text(out_path.name, raw) or (
        raw if "-->" in raw else None
    )


def extract_embedded_softsubs_from_url(url: str) -> dict[Lang, str]:
    """Blocking helper: probe + extract EN/ZH text softsubs from a media URL."""
    if not url or not shutil.which(_ffprobe_bin()):
        return {}
    streams = _probe_subtitle_streams(url)
    if not streams:
        return {}

    tmp = Path(tempfile.mkdtemp(prefix="ae-embsub-"))
    try:
        candidates: list[tuple[Lang, int, str]] = []
        und_bodies: list[str] = []
        for stream in streams:
            if not isinstance(stream, dict):
                continue
            codec = str(stream.get("codec_name") or "").lower()
            if codec in _BITMAP_CODECS:
                continue
            if codec and codec not in _TEXT_CODECS and not codec.endswith("text"):
                # Unknown: still try extract; skip obvious bitmap-ish names.
                if "pgs" in codec or "dvd" in codec or "dvb" in codec:
                    continue
            try:
                index = int(stream.get("index"))
            except (TypeError, ValueError):
                continue
            out = tmp / f"s{index}.srt"
            try:
                body = _extract_stream_to_srt(url, stream_index=index, out_path=out)
            except Exception:  # noqa: BLE001
                body = None
            if not body or "-->" not in body:
                continue
            lang = _tag_lang(stream.get("tags") if isinstance(stream.get("tags"), dict) else None)
            if lang is None:
                und_bodies.append(body)
                continue
            candidates.append((lang, index, body))

        out: dict[Lang, str] = {}
        # Prefer first track per language (lower stream index first).
        for lang, _idx, body in sorted(candidates, key=lambda row: row[1]):
            out.setdefault(lang, body)

        for body in und_bodies:
            sniffed = _sniff_lang(body)
            out.setdefault(sniffed, body)

        # Single und track assigned to en but Chinese → flip.
        if "en" in out and "zh" not in out and _srt_looks_chinese(out["en"]):
            out["zh"] = out.pop("en")
        return out
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


async def extract_embedded_softsubs(
    client: OpenListClient,
    video_path: str,
) -> dict[Lang, str]:
    """Resolve OpenList raw URL and extract embedded text softsubs (async)."""
    if not supports_embedded_softsubs(video_path):
        return {}
    try:
        meta = await client.fs_get(video_path)
    except OpenListError:
        return {}
    raw_url = str(meta.get("raw_url") or "").strip() or public_raw_url(video_path)
    if not raw_url:
        return {}
    return await asyncio.to_thread(extract_embedded_softsubs_from_url, raw_url)
