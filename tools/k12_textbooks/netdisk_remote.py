"""ECS-side helpers: scan Baidu textbook tree and resolve download URLs via OpenList."""

from __future__ import annotations

import argparse
import asyncio
import json
import re
import sys
from pathlib import Path

# Allow `PYTHONPATH=/tmp/k12_textbooks_helpers:.`
sys.path.insert(0, str(Path(__file__).resolve().parent))

from app.services.openlist_client import OpenListClient, OpenListError

from scan_local import _GRADE_MAP, _VOLUME_MAP, _match_edition

DEFAULT_ROOT = (
    "/ae-u44-baidu/小初高/2026年小初高教材（版本齐全）/"
    "2026年最新中小学教材电子书汇总（9月最新）"
)

_AUDIO_EXT = {".mp3", ".m4a", ".wav"}
_BOOK_EXT = {".pdf", ".epub"}


def _leaf_stats(rows: list[dict]) -> dict:
    files = [r for r in rows if not r.get("is_dir")]
    dirs = [r for r in rows if r.get("is_dir")]
    pdf = sum(
        1
        for r in files
        if Path(str(r.get("name") or "")).suffix.lower() in _BOOK_EXT
    )
    mp3 = sum(
        1
        for r in files
        if Path(str(r.get("name") or "")).suffix.lower() in _AUDIO_EXT
    )
    return {
        "pdf": pdf,
        "mp3": mp3,
        "files": len(files),
        "dirs": len(dirs),
        "dir_names": [str(r.get("name") or "") for r in dirs],
    }


async def _pick_content_folder(client: OpenListClient, path: str) -> tuple[str, dict]:
    rows = await client.fs_list_all(path)
    stats = _leaf_stats(rows)
    if stats["pdf"] >= 1 and stats["mp3"] >= 5:
        return path, stats

    year_dirs = [
        name
        for name in stats["dir_names"]
        if re.search(r"20\d{2}", name) or "年度" in name
    ]
    year_dirs.sort(reverse=True)
    for name in year_dirs:
        child = f"{path.rstrip('/')}/{name}"
        child_rows = await client.fs_list_all(child)
        child_stats = _leaf_stats(child_rows)
        if child_stats["pdf"] >= 1 and child_stats["mp3"] >= 5:
            return child, child_stats
    return path, stats


def _is_pep_edition(folder_name: str) -> bool:
    """人教系：PEP / 一年级起点 / Go for it / 初高中「人教版」。"""
    name = folder_name or ""
    if "人教" in name or re.search(r"PEP", name, re.I):
        return True
    if re.search(r"Go\s*for\s*it", name, re.I):
        return True
    return False


async def scan_english_root(
    english_path: str,
    *,
    stage: str,
    stage_key: str,
    hot_only: bool = True,
    pep_only: bool = True,
) -> list[dict]:
    """Scan one stage English folder (editions directly under path)."""
    client = OpenListClient()
    english_path = english_path.rstrip("/")
    out: list[dict] = []
    try:
        editions = await client.fs_list_all(english_path)
    except OpenListError:
        return out

    for edition_row in editions:
        if not edition_row.get("is_dir"):
            continue
        edition_name = str(edition_row.get("name") or "")
        if pep_only and not _is_pep_edition(edition_name):
            continue
        edition_key, edition, publisher, score, hot = _match_edition(edition_name)
        if hot_only and not hot:
            continue
        edition_path = f"{english_path}/{edition_name}"
        grades = await client.fs_list_all(edition_path)
        for grade_row in grades:
            if not grade_row.get("is_dir"):
                continue
            grade_name = str(grade_row.get("name") or "")
            if grade_name not in _GRADE_MAP:
                continue
            grade_id, mapped_stage, level = _GRADE_MAP[grade_name]
            # Prefer caller stage_key; grade map still supplies level.
            stage_key_out = stage_key or mapped_stage
            grade_path = f"{edition_path}/{grade_name}"
            volumes = await client.fs_list_all(grade_path)
            for volume_row in volumes:
                if not volume_row.get("is_dir"):
                    continue
                volume_name = str(volume_row.get("name") or "")
                if volume_name not in _VOLUME_MAP:
                    continue
                volume_key, volume_label = _VOLUME_MAP[volume_name]
                volume_path = f"{grade_path}/{volume_name}"
                content_path, stats = await _pick_content_folder(client, volume_path)
                ready = stats["pdf"] >= 1 and stats["mp3"] >= 5
                grade_short = grade_id.replace("k12_", "")
                book_id = f"{edition_key}-{grade_short}-{volume_key}"
                out.append(
                    {
                        "remote_path": content_path,
                        "stage": stage,
                        "stage_key": stage_key_out,
                        "edition_folder": edition_name,
                        "edition_key": edition_key,
                        "edition": edition,
                        "publisher": publisher,
                        "grade_label": grade_name,
                        "grade_id": grade_id,
                        "volume_label": volume_label,
                        "volume_key": volume_key,
                        "level": level,
                        "book_id": book_id,
                        "catalog_id": (
                            f"k12-textbook:{edition_key}:{grade_id}:{volume_key}"
                        ),
                        "hot": hot,
                        "score": score + min(20, stats["mp3"] // 5),
                        "pdf_count": stats["pdf"],
                        "mp3_count": stats["mp3"],
                        "ready": ready,
                        "local_rel": (
                            f"{stage}/英语/{edition_name}/{grade_name}/{volume_name}"
                        ),
                    }
                )
    out.sort(
        key=lambda row: (
            -int(row["score"]),
            row["edition_folder"],
            row["grade_id"],
            row["volume_key"],
        )
    )
    return out


async def scan_netdisk(
    root: str,
    *,
    hot_only: bool = True,
    pep_only: bool = True,
) -> list[dict]:
    client = OpenListClient()
    root = root.rstrip("/")
    wanted_stages = [
        ("小学", "primary"),
        ("初中", "junior"),
        ("高中", "senior"),
    ]
    out: list[dict] = []

    top = await client.fs_list_all(root)
    stage_names = {
        str(r.get("name") or "")
        for r in top
        if r.get("is_dir")
    }
    for stage, stage_key in wanted_stages:
        if stage not in stage_names:
            continue
        english_path = f"{root}/{stage}/英语"
        rows = await scan_english_root(
            english_path,
            stage=stage,
            stage_key=stage_key,
            hot_only=hot_only,
            pep_only=pep_only,
        )
        out.extend(rows)
    out.sort(
        key=lambda row: (
            -int(row["score"]),
            row["edition_folder"],
            row["grade_id"],
            row["volume_key"],
        )
    )
    return out


async def list_downloadable_files(path: str) -> list[dict]:
    client = OpenListClient()
    rows = await client.fs_list_all(path)
    files: list[dict] = []
    for row in rows:
        if row.get("is_dir"):
            continue
        name = str(row.get("name") or "")
        if not name or name in (".", ".."):
            continue
        suffix = Path(name).suffix.lower()
        if suffix not in _AUDIO_EXT and suffix not in _BOOK_EXT:
            continue
        files.append(
            {
                "name": name,
                "size": int(row.get("size") or 0),
                "path": f"{path.rstrip('/')}/{name}",
            }
        )
    files.sort(key=lambda item: item["name"].lower())
    return files


async def resolve_raw_urls(paths: list[str]) -> list[dict]:
    client = OpenListClient()
    out: list[dict] = []
    for path in paths:
        item = await client.fs_get(path)
        out.append(
            {
                "path": path,
                "name": str(item.get("name") or Path(path).name),
                "size": int(item.get("size") or 0),
                "raw_url": str(item.get("raw_url") or ""),
            }
        )
    return out


def _load_job(path: str | None) -> dict:
    if not path:
        return {}
    return json.loads(Path(path).read_text(encoding="utf-8"))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "command",
        choices=("scan", "scan_stages", "files", "resolve"),
    )
    parser.add_argument("--job", default="", help="JSON job file")
    args = parser.parse_args()
    job = _load_job(args.job or None)

    if args.command == "scan":
        root = str(job.get("root") or DEFAULT_ROOT)
        hot_only = bool(job.get("hot_only", True))
        pep_only = bool(job.get("pep_only", True))
        rows = asyncio.run(
            scan_netdisk(root, hot_only=hot_only, pep_only=pep_only)
        )
        print(json.dumps({"count": len(rows), "books": rows}, ensure_ascii=False))
        return 0
    if args.command == "scan_stages":
        stages = job.get("stages") or []
        if not isinstance(stages, list) or not stages:
            raise SystemExit("job.stages required")
        hot_only = bool(job.get("hot_only", True))
        pep_only = bool(job.get("pep_only", True))
        all_rows: list[dict] = []
        for stage in stages:
            if not isinstance(stage, dict):
                continue
            english_path = str(stage.get("personal_root") or "").strip()
            if not english_path:
                continue
            rows = asyncio.run(
                scan_english_root(
                    english_path,
                    stage=str(stage.get("stage") or ""),
                    stage_key=str(stage.get("stage_key") or ""),
                    hot_only=hot_only,
                    pep_only=pep_only,
                )
            )
            share_url = str(stage.get("share_url") or "")
            share_pwd = str(stage.get("pwd") or "")
            stage_key = str(stage.get("stage_key") or "")
            for row in rows:
                row["share_stage"] = stage_key
                row["source_share_url"] = share_url
                row["source_share_pwd"] = share_pwd
            all_rows.extend(rows)
        all_rows.sort(
            key=lambda row: (
                -int(row["score"]),
                row["edition_folder"],
                row["grade_id"],
                row["volume_key"],
            )
        )
        print(
            json.dumps(
                {"count": len(all_rows), "books": all_rows},
                ensure_ascii=False,
            )
        )
        return 0
    if args.command == "files":
        path = str(job.get("path") or "")
        if not path:
            raise SystemExit("job.path required")
        files = asyncio.run(list_downloadable_files(path))
        print(json.dumps({"path": path, "files": files}, ensure_ascii=False))
        return 0
    if args.command == "resolve":
        paths = job.get("paths") or []
        if not isinstance(paths, list) or not paths:
            raise SystemExit("job.paths required")
        rows = asyncio.run(resolve_raw_urls([str(p) for p in paths]))
        print(json.dumps({"files": rows}, ensure_ascii=False))
        return 0
    raise SystemExit("unknown command")


if __name__ == "__main__":
    raise SystemExit(main())
