"""Bounded recursive book discovery in a user's own mounted cloud drive."""

from __future__ import annotations

import re
from pathlib import PurePosixPath
from typing import Any

from app.services.openlist_client import OpenListClient

BOOK_EXTENSIONS = (".epub", ".pdf", ".mobi", ".azw3", ".txt")
FORMAT_RANK = {suffix: index for index, suffix in enumerate(BOOK_EXTENSIONS)}


def _variant(path: str) -> str:
    lower = path.lower()
    if any(token in lower for token in ("中文版", "中文", "chinese", "简体", "繁体")):
        return "中文"
    if any(token in lower for token in ("美版", "美式", "american", " us ")):
        return "美版"
    if any(token in lower for token in ("英版", "英式", "british", " uk ")):
        return "英版"
    return "未标注版本"


def _book_key(path: str) -> tuple[str, str]:
    name = PurePosixPath(path).stem.lower()
    name = re.sub(r"(中文版|英版|美版|简体|繁体|chinese|british|american)", "", name)
    name = re.sub(r"[^\w\u4e00-\u9fff]+", "", name)
    return (name, _variant(path))


def choose_book_formats(paths: list[str], *, epub_only: bool = False) -> list[dict[str, str]]:
    """Keep one format for each title and language edition; EPUB wins."""
    chosen: dict[tuple[str, str], str] = {}
    for path in paths:
        suffix = PurePosixPath(path).suffix.lower()
        if suffix not in FORMAT_RANK or (epub_only and suffix != ".epub"):
            continue
        key = _book_key(path)
        if not key[0]:
            continue
        previous = chosen.get(key)
        if previous is None or FORMAT_RANK[suffix] < FORMAT_RANK[PurePosixPath(previous).suffix.lower()]:
            chosen[key] = path
    return [
        {"title": PurePosixPath(path).stem, "variant": variant,
         "format": PurePosixPath(path).suffix.lower().lstrip("."), "path": path}
        for (_, variant), path in sorted(chosen.items(), key=lambda pair: pair[1].lower())
    ]


async def scan_book_folder(client: OpenListClient, root: str,
                           *, max_depth: int = 10, max_entries: int = 2000,
                           epub_only: bool = False) -> list[dict[str, str]]:
    folders: list[tuple[str, int]] = [(root.rstrip("/"), 0)]
    files: list[str] = []
    examined = 0
    while folders:
        folder, depth = folders.pop(0)
        rows: list[dict[str, Any]] = await client.fs_list_all(folder)
        examined += len(rows)
        if examined > max_entries:
            raise ValueError("文件夹内容过多，请选择更小的子文件夹")
        for row in rows:
            name = str(row.get("name") or "")
            if not name or name in (".", "..") or "/" in name or "\\" in name:
                continue
            child = f"{folder}/{name}"
            if row.get("is_dir"):
                if depth < max_depth:
                    folders.append((child, depth + 1))
            elif PurePosixPath(name).suffix.lower() in BOOK_EXTENSIONS:
                files.append(child)
    return choose_book_formats(files, epub_only=epub_only)
