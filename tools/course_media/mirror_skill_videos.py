#!/usr/bin/env python3
"""Mirror homepage skill-module lesson videos onto ECS /media/course.

Run on the 5060 Ti workstation (has yt-dlp in tools/subtitle .venv), then scp:

  tools/subtitle/.venv/Scripts/python.exe tools/course_media/mirror_skill_videos.py \\
      --series british_ipa_bbc --pages 2-5 --out D:\\AcquireEnglish\\tmp\\course_videos

  # upload one series folder
  scp -r D:\\AcquireEnglish\\tmp\\course_videos\\british_ipa_bbc \\
      root@8.163.45.100:/opt/acquireenglish/services/api/media/course/

Layout written:

  {out}/{series_id}/{nn}/video.mp4
"""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

SERIES = {
    "oral_core_9000": "BV1CS4y1v7sQ",
    "british_ipa_bbc": "BV127411n7nj",
    "american_ipa_20": "BV1iy4y1v7WQ",
    "phonics_nessy": "BV1Qg4mzKENh",
}


def _parse_pages(raw: str) -> list[int]:
    text = (raw or "").strip()
    if not text:
        return []
    out: list[int] = []
    for part in text.split(","):
        part = part.strip()
        if not part:
            continue
        if "-" in part:
            a, b = part.split("-", 1)
            start, end = int(a), int(b)
            out.extend(range(start, end + 1))
        else:
            out.append(int(part))
    return sorted(set(out))


def _download(bvid: str, page: int, dest: Path) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    url = f"https://www.bilibili.com/video/{bvid}?p={page}"
    cmd = [
        sys.executable,
        "-m",
        "yt_dlp",
        "--no-playlist",
        "-f",
        "bv*[height<=720]+ba/b[height<=720]/b",
        "--merge-output-format",
        "mp4",
        "-o",
        str(dest),
        url,
    ]
    print(" ".join(cmd), flush=True)
    subprocess.check_call(cmd)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--series", required=True, choices=sorted(SERIES))
    parser.add_argument("--pages", required=True, help="e.g. 1-5 or 2,3,4")
    parser.add_argument("--out", required=True, help="Local output root")
    parser.add_argument("--skip-existing", action="store_true")
    args = parser.parse_args()
    bvid = SERIES[args.series]
    root = Path(args.out).expanduser() / args.series
    pages = _parse_pages(args.pages)
    if not pages:
        raise SystemExit("no pages")
    for page in pages:
        dest = root / f"{page:02d}" / "video.mp4"
        if args.skip_existing and dest.is_file() and dest.stat().st_size > 64 * 1024:
            print(f"skip existing {dest}")
            continue
        _download(bvid, page, dest)
    print(f"done series={args.series} pages={pages} root={root}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
