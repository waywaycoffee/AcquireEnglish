"""Download / extract a short audio clip for ASR."""

from __future__ import annotations

import re
import subprocess
import tempfile
from pathlib import Path

import httpx

from app.link_import import _BV, _YT_ID, _bilibili_headers

# Hard cap to bound cost/timeout (3 hours). Callers should pass lesson duration.
MAX_SECONDS = 3 * 60 * 60
FFMPEG_BIN = next(
    (
        p
        for p in (
            "/usr/bin/ffmpeg",
            "/usr/local/bin/ffmpeg",
            "ffmpeg",
        )
        if p == "ffmpeg" or Path(p).exists()
    ),
    "ffmpeg",
)


def _run(cmd: list[str]) -> None:
    proc = subprocess.run(cmd, capture_output=True, text=True)
    if proc.returncode != 0:
        err = (proc.stderr or proc.stdout or "").strip()
        raise RuntimeError(err[-500:] or f"command failed: {cmd[0]}")


async def extract_audio_for_url(
    watch_url: str,
    *,
    bilibili_cookie: str | None = None,
    max_seconds: int = MAX_SECONDS,
) -> Path:
    """Return path to a temporary mp3 suitable for ASR."""
    tmp = Path(tempfile.mkdtemp(prefix="ae-asr-"))
    out = tmp / "audio.mp3"

    if _BV.search(watch_url) or "bilibili.com" in watch_url:
        await _extract_bilibili(watch_url, out, cookie=bilibili_cookie, max_seconds=max_seconds)
        return out

    if _YT_ID.search(watch_url) or "youtu" in watch_url:
        _extract_ytdlp(watch_url, out, max_seconds=max_seconds)
        return out

    if watch_url.startswith("http"):
        await _extract_http_media(watch_url, out, max_seconds=max_seconds)
        return out

    raise ValueError("无法从该链接提取音频")


async def _extract_bilibili(
    watch_url: str,
    out: Path,
    *,
    cookie: str | None,
    max_seconds: int,
) -> None:
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
            raise ValueError("缺少 cid，无法下载音频")

        play = await client.get(
            "https://api.bilibili.com/x/player/playurl",
            params={"bvid": bvid, "cid": cid, "fnval": 16, "fourk": 1},
        )
        play.raise_for_status()
        play_root = play.json()
        if play_root.get("code") != 0:
            raise ValueError(play_root.get("message") or "无法获取音频流")
        dash = ((play_root.get("data") or {}).get("dash") or {})
        audio_list = dash.get("audio") or []
        if not audio_list:
            raise ValueError("该视频没有可下载的音频流")
        # Prefer mid quality.
        audio_list = sorted(audio_list, key=lambda a: int(a.get("bandwidth") or 0))
        audio_url = audio_list[len(audio_list) // 2].get("baseUrl") or audio_list[0].get("base_url")
        if not audio_url:
            raise ValueError("音频地址为空")

        dl_headers = {
            "User-Agent": (
                "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
                "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"
            ),
            "Referer": "https://www.bilibili.com",
            "Accept": "*/*",
        }
        if cookie:
            dl_headers["Cookie"] = cookie.strip()
        raw = out.with_suffix(".m4a")
        async with httpx.AsyncClient(timeout=120.0, follow_redirects=True) as dl:
            async with dl.stream("GET", audio_url, headers=dl_headers) as resp:
                resp.raise_for_status()
                with raw.open("wb") as f:
                    async for chunk in resp.aiter_bytes():
                        f.write(chunk)

    _ffmpeg_trim(raw, out, max_seconds=max_seconds)
    try:
        raw.unlink(missing_ok=True)
    except Exception:
        pass


def _extract_ytdlp(watch_url: str, out: Path, *, max_seconds: int) -> None:
    section = f"*0-{max_seconds}"
    target = out.parent / "ytdlp_audio.%(ext)s"
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
        raise ValueError("服务器未安装 yt-dlp，暂无法处理 YouTube 音频") from exc
    produced = out.parent / "ytdlp_audio.mp3"
    if not produced.exists():
        matches = list(out.parent.glob("ytdlp_audio.*"))
        if not matches:
            raise RuntimeError("yt-dlp 未生成音频")
        produced = matches[0]
    if produced != out:
        produced.replace(out)

async def _extract_http_media(url: str, out: Path, *, max_seconds: int) -> None:
    raw = out.with_suffix(".bin")
    async with httpx.AsyncClient(timeout=120.0, follow_redirects=True) as client:
        async with client.stream("GET", url) as resp:
            resp.raise_for_status()
            with raw.open("wb") as f:
                async for chunk in resp.aiter_bytes():
                    f.write(chunk)
    _ffmpeg_trim(raw, out, max_seconds=max_seconds)
    raw.unlink(missing_ok=True)


def _ffmpeg_trim(src: Path, dest_mp3: Path, *, max_seconds: int) -> None:
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
            "16000",
            "-b:a",
            "64k",
            str(dest_mp3),
        ]
    )


def parse_import_id(course_id: str) -> int | None:
    m = re.fullmatch(r"link-(\d+)", course_id or "")
    return int(m.group(1)) if m else None
