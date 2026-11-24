"""Match and load sidecar subtitle files next to a netdisk video."""

from __future__ import annotations

import re
from pathlib import PurePosixPath
from typing import Literal

import httpx

from app.link_import import _srt_looks_chinese, _vtt_to_srt
from app.services.openlist_client import OpenListClient, OpenListError, public_raw_url

SUBTITLE_SUFFIXES = (".srt", ".vtt", ".ass", ".ssa")
Lang = Literal["en", "zh"]

_EN_TOKENS = ("en", "eng", "english", "en-us", "en_us", "en-gb", "en_gb")
_ZH_TOKENS = (
    "zh",
    "zh-cn",
    "zh_cn",
    "zh-hans",
    "zh_hans",
    "chs",
    "chi",
    "cn",
    "chinese",
)


def is_subtitle_name(name: str) -> bool:
    lower = name.lower()
    return any(lower.endswith(suf) for suf in SUBTITLE_SUFFIXES)


def video_stem(name: str) -> str:
    return PurePosixPath(name).stem


def _token_lang(stem: str, video: str) -> Lang | None:
    """Classify `video.en` / `video.zh` style stems relative to the video stem."""
    lower = stem.lower()
    v = video.lower()
    if lower == v:
        return None
    if not (lower.startswith(v + ".") or lower.startswith(v + "_") or lower.startswith(v + "-")):
        return None
    token = lower[len(v) + 1 :].replace("_", "-")
    head = token.split("-", 1)[0] if token else ""
    packed = token.replace("-", "")
    for cand in (token, head, packed):
        if cand in _EN_TOKENS or cand.replace("-", "_") in _EN_TOKENS:
            return "en"
        if cand in _ZH_TOKENS or cand.replace("-", "_") in _ZH_TOKENS:
            return "zh"
    if "english" in token:
        return "en"
    if any(t in token for t in ("chinese", "简体", "中文")):
        return "zh"
    return None


def assign_sidecar_paths(
    video_filename: str,
    sibling_names: list[str],
    *,
    plain_bodies: dict[str, str] | None = None,
) -> dict[Lang, str]:
    """Return {en|zh: sibling filename}. Uses text sniff for plain `.srt` when needed."""
    vstem = video_stem(video_filename)
    out: dict[Lang, str] = {}
    plain: list[str] = []
    for name in sibling_names:
        if not is_subtitle_name(name):
            continue
        stem = video_stem(name)
        if stem.lower() == vstem.lower():
            plain.append(name)
            continue
        lang = _token_lang(stem, vstem)
        if lang and lang not in out:
            out[lang] = name

    bodies = plain_bodies or {}
    for name in plain:
        if "en" in out and "zh" in out:
            break
        body = bodies.get(name, "")
        if body and _srt_looks_chinese(body):
            if "zh" not in out:
                out["zh"] = name
        else:
            if "en" not in out:
                out["en"] = name
            elif "zh" not in out and body and _srt_looks_chinese(body):
                out["zh"] = name
    # Single plain file with no body yet → prefer EN slot (filled later after fetch).
    if plain and "en" not in out and "zh" not in out:
        out["en"] = plain[0]
    elif plain and "en" not in out and "zh" in out:
        for name in plain:
            if name != out.get("zh"):
                out["en"] = name
                break
    elif plain and "zh" not in out and "en" in out:
        for name in plain:
            if name != out.get("en"):
                # defer zh until sniff; keep second plain as candidate zh
                out.setdefault("zh", name)
                break
    return out


def _ass_time_to_srt(ts: str) -> str:
    """Convert ASS `H:MM:SS.cs` to SRT `HH:MM:SS,mmm`."""
    parts = ts.strip().split(":")
    if len(parts) != 3:
        return "00:00:00,000"
    try:
        hours = int(parts[0])
        minutes = int(parts[1])
        sec_parts = parts[2].split(".")
        seconds = int(sec_parts[0])
        centis = int((sec_parts[1] + "00")[:2]) if len(sec_parts) > 1 else 0
        millis = centis * 10
    except ValueError:
        return "00:00:00,000"
    return f"{hours:02d}:{minutes:02d}:{seconds:02d},{millis:03d}"


def _ass_to_srt(raw: str) -> str | None:
    """Extract Dialogue lines from ASS/SSA into basic SRT."""
    cues: list[str] = []
    index = 1
    for line in raw.splitlines():
        if not line.startswith("Dialogue:"):
            continue
        body = line[len("Dialogue:") :].strip()
        fields = body.split(",", 9)
        if len(fields) < 10:
            continue
        start = _ass_time_to_srt(fields[1])
        end = _ass_time_to_srt(fields[2])
        text = fields[9]
        text = re.sub(r"\{[^}]*\}", "", text)
        text = text.replace(r"\N", "\n").replace(r"\n", "\n").strip()
        if not text:
            continue
        cues.append(f"{index}\n{start} --> {end}\n{text}\n")
        index += 1
    if not cues:
        return None
    return "\n".join(cues) + "\n"


def normalize_subtitle_text(filename: str, raw: str) -> str | None:
    text = (raw or "").strip()
    if not text:
        return None
    lower = filename.lower()
    if lower.endswith(".vtt") or text.lstrip().startswith("WEBVTT"):
        return _vtt_to_srt(text)
    if lower.endswith(".ass") or lower.endswith(".ssa"):
        return _ass_to_srt(text)
    # Assume SRT / plain cue text.
    if "-->" in text:
        return text if text.endswith("\n") else text + "\n"
    return None


async def fetch_openlist_text(client: OpenListClient, path: str) -> str | None:
    """Download a small sidecar text file via OpenList raw_url."""
    try:
        meta = await client.fs_get(path)
    except OpenListError:
        return None
    raw_url = str(meta.get("raw_url") or "").strip() or public_raw_url(path)
    try:
        async with httpx.AsyncClient(follow_redirects=True, timeout=60.0) as http:
            resp = await http.get(
                raw_url,
                headers={"User-Agent": "pan.baidu.com"},
            )
            if resp.status_code >= 400:
                return None
            # Prefer utf-8; fall back to gbk for legacy Chinese SRT.
            try:
                return resp.content.decode("utf-8")
            except UnicodeDecodeError:
                return resp.content.decode("gb18030", errors="replace")
    except Exception:  # noqa: BLE001
        return None


async def load_sidecars_for_video(
    client: OpenListClient,
    video_path: str,
    *,
    dir_cache: dict[str, list[str]] | None = None,
) -> dict[Lang, str]:
    """List the parent folder, match sidecars, return {en|zh: srt body}.

    ``dir_cache`` caches subtitle filenames per parent folder so bulk series
    import does not re-list the same Season directory for every episode.
    """
    parent = str(PurePosixPath(video_path).parent)
    video_name = PurePosixPath(video_path).name
    names: list[str] | None = None
    if dir_cache is not None and parent in dir_cache:
        names = dir_cache[parent]
    else:
        try:
            data = await client.fs_list(parent)
        except OpenListError:
            return {}
        content = data.get("content") if isinstance(data, dict) else None
        names = []
        if isinstance(content, list):
            for item in content:
                if not isinstance(item, dict) or item.get("is_dir"):
                    continue
                name = str(item.get("name") or "")
                if is_subtitle_name(name):
                    names.append(name)
        if dir_cache is not None:
            dir_cache[parent] = names
    if not names:
        return {}

    # First pass: tagged names without bodies.
    tentative = assign_sidecar_paths(video_name, names)
    # Fetch all candidates that might be needed (tagged + plain same-stem).
    vstem = video_stem(video_name)
    candidates = set(tentative.values())
    for name in names:
        if video_stem(name).lower() == vstem.lower():
            candidates.add(name)

    bodies: dict[str, str] = {}
    normalized: dict[str, str] = {}
    for name in candidates:
        path = f"{parent.rstrip('/')}/{name}"
        raw = await fetch_openlist_text(client, path)
        if not raw:
            continue
        srt = normalize_subtitle_text(name, raw)
        if not srt:
            continue
        bodies[name] = srt
        normalized[name] = srt

    assigned = assign_sidecar_paths(video_name, names, plain_bodies=bodies)
    out: dict[Lang, str] = {}
    for lang, name in assigned.items():
        body = normalized.get(name)
        if body:
            out[lang] = body  # type: ignore[index]
    # If only one plain body and assigned to en but looks Chinese, swap.
    if "en" in out and "zh" not in out and _srt_looks_chinese(out["en"]):
        out["zh"] = out.pop("en")
    return out
