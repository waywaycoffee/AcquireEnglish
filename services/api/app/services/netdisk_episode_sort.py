"""Sort netdisk video filenames like local ImportMatcher (SxxExx / ep / numbers)."""

from __future__ import annotations

import re
from pathlib import PurePosixPath


_SXXEXX = re.compile(r"[Ss](\d{1,2})[Ee](\d{1,3})")
_DASHED = re.compile(r"(?<!\d)(\d{1,2})[-_](\d{1,3})(?!\d)")
_EP = re.compile(r"(?:^|[^\d])(?:[Ee][Pp]?)?(\d{1,3})(?:[^\d]|$)")


def episode_sort_key(filename: str) -> tuple[int, int, str]:
    """Return (season, episode, lower_name) for stable TV-style ordering."""
    name = PurePosixPath(filename).name
    stem = PurePosixPath(name).stem
    m = _SXXEXX.search(stem)
    if m:
        return (int(m.group(1)), int(m.group(2)), name.lower())
    m = _DASHED.search(stem)
    if m:
        return (int(m.group(1)), int(m.group(2)), name.lower())
    m = _EP.search(stem)
    if m:
        return (0, int(m.group(1)), name.lower())
    return (0, 10_000, name.lower())


def sort_video_paths(paths: list[str]) -> list[str]:
    return sorted(paths, key=lambda p: episode_sort_key(PurePosixPath(p).name))
