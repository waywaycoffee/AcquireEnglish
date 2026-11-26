#!/usr/bin/env python3
"""Batch-import local 人教版 PDF+MP3 into ECS media/reading/k12."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from import_book import main as import_one_main  # noqa: E402
from scan_local import ROOT_DEFAULT, import_command, scan_local_tree  # noqa: E402


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=ROOT_DEFAULT)
    parser.add_argument("--limit", type=int, default=0)
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--book-id", action="append", default=[])
    parser.add_argument("--json-out", type=Path, default=None)
    args = parser.parse_args()

    rows = [
        r
        for r in scan_local_tree(
            args.root,
            hot_only=False,
            pep_only=True,
            min_mp3=5,
            latest_year_only=True,
        )
        if r.ready
    ]
    if args.book_id:
        wanted = set(args.book_id)
        rows = [r for r in rows if r.book_id in wanted]
    if args.limit > 0:
        rows = rows[: args.limit]

    print(f"将入库人教 {len(rows)} 册 → ECS media/reading/k12", flush=True)
    for row in rows:
        print(
            f"- {row.book_id}  mp3={row.mp3_count}  {row.path}",
            flush=True,
        )
        if args.dry_run:
            print(f"  {import_command(row)}", flush=True)

    if args.json_out:
        args.json_out.parent.mkdir(parents=True, exist_ok=True)
        args.json_out.write_text(
            json.dumps(
                {"count": len(rows), "books": [r.to_dict() for r in rows]},
                ensure_ascii=False,
                indent=2,
            ),
            encoding="utf-8",
        )
        print(f"wrote {args.json_out}", flush=True)

    if args.dry_run or not rows:
        return 0

    ok = 0
    failed: list[str] = []
    for row in rows:
        argv = [
            "import_book.py",
            "--source",
            row.path,
            "--book-id",
            row.book_id,
            "--catalog-id",
            row.catalog_id,
            "--title",
            row.title,
            "--title-zh",
            row.title_zh,
            "--edition",
            row.edition,
            "--publisher",
            row.publisher or row.edition,
            "--grade-id",
            row.grade_id,
            "--stage",
            row.stage,
            "--volume",
            row.volume_label,
            "--level",
            row.level,
        ]
        sys.argv = argv
        try:
            code = import_one_main()
        except SystemExit as exc:
            code = int(exc.code or 1)
        except Exception as exc:  # noqa: BLE001
            print(f"! fail {row.book_id}: {exc}", flush=True)
            failed.append(row.book_id)
            continue
        if code == 0:
            ok += 1
        else:
            failed.append(row.book_id)
            print(f"! fail {row.book_id} exit={code}", flush=True)

    print(
        json.dumps({"ok": ok, "failed": failed, "total": len(rows)}, ensure_ascii=False),
        flush=True,
    )
    return 0 if not failed else 1


if __name__ == "__main__":
    raise SystemExit(main())
