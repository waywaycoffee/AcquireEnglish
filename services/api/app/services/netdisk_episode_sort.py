"""Sort netdisk video filenames like local ImportMatcher (SxxExx / ep / numbers)."""

from __future__ import annotations

import re
from pathlib import PurePosixPath


_SXXEXX = re.compile(r"[Ss](\d{1,2})[Ee](\d{1,3})")
# Chinese netdisk packs: SE01 (1).mkv / 1080P.SE02 (17).mkv
_SE_PAREN = re.compile(r"[Ss][Ee](\d{1,2})\s*[\(\[（]\s*(\d{1,3})\s*[\)\]）]")
_FOLDER_SEASON = re.compile(r"(?:^|/)[Ss](\d{1,2})(?:/|$)")
_DASHED = re.compile(r"(?<!\d)(\d{1,2})[-_](\d{1,3})(?!\d)")
_EP = re.compile(r"(?:^|[^\d])(?:[Ee][Pp]?)?(\d{1,3})(?:[^\d]|$)")


def parse_season_episode(path_or_name: str) -> tuple[int, int] | None:
    """Extract (season, episode) from a video/subtitle path or filename."""
    raw = path_or_name or ""
    name = PurePosixPath(raw).name
    stem = PurePosixPath(name).stem
    m = _SXXEXX.search(stem) or _SXXEXX.search(raw)
    if m:
        return (int(m.group(1)), int(m.group(2)))
    m = _SE_PAREN.search(stem) or _SE_PAREN.search(name)
    if m:
        return (int(m.group(1)), int(m.group(2)))
    m = _DASHED.search(stem)
    if m:
        return (int(m.group(1)), int(m.group(2)))
    folder = _FOLDER_SEASON.search(raw.replace("\\", "/"))
    if folder:
        season = int(folder.group(1))
        m = _EP.search(stem)
        if m:
            return (season, int(m.group(1)))
    return None


def episode_sort_key(filename: str) -> tuple[int, int, str]:
    """Return (season, episode, lower_name) for stable TV-style ordering."""
    name = PurePosixPath(filename).name
    parsed = parse_season_episode(filename)
    if parsed is not None:
        return (parsed[0], parsed[1], name.lower())
    stem = PurePosixPath(name).stem
    m = _EP.search(stem)
    if m:
        return (0, int(m.group(1)), name.lower())
    return (0, 10_000, name.lower())


def sort_video_paths(paths: list[str]) -> list[str]:
    return sorted(paths, key=lambda p: episode_sort_key(p))
