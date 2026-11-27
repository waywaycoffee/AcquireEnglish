#!/usr/bin/env python3
"""Upload ECS ``media_cache_dir`` blobs to Aliyun OSS.

Usage (on API host)::

    cd /opt/acquireenglish/services/api
    .venv/bin/python scripts/migrate_media_to_oss.py --dry-run
    .venv/bin/python scripts/migrate_media_to_oss.py
    .venv/bin/python scripts/migrate_media_to_oss.py --skip-existing

Requires ``OSS_ENABLED=1`` and bucket credentials in ``.env``.
Does **not** delete local files unless ``--delete-local-after`` is set.
"""

from __future__ import annotations

import argparse
import sys
import time
from pathlib import Path

# Allow ``python scripts/migrate_media_to_oss.py`` from services/api.
_ROOT = Path(__file__).resolve().parents[1]
if str(_ROOT) not in sys.path:
    sys.path.insert(0, str(_ROOT))

from app.config import settings  # noqa: E402
from app.services import oss_storage  # noqa: E402
from app.services.content_media import media_cache_root  # noqa: E402


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument(
        "--skip-existing",
        action="store_true",
        help="Skip objects that already exist on OSS (HEAD).",
    )
    parser.add_argument(
        "--delete-local-after",
        action="store_true",
        help="Delete each local file after a successful upload (irreversible).",
    )
    parser.add_argument(
        "--prefix",
        default="",
        help="Only migrate relative paths under this prefix (e.g. reading/).",
    )
    args = parser.parse_args()

    if not oss_storage.oss_configured():
        print(
            "OSS is not configured. Set OSS_ENABLED=1, OSS_BUCKET, "
            "OSS_ENDPOINT, OSS_ACCESS_KEY_ID, OSS_ACCESS_KEY_SECRET "
            "(and preferably OSS_PUBLIC_BASE) in services/api/.env",
            file=sys.stderr,
        )
        return 2

    root = media_cache_root().resolve()
    prefix = (args.prefix or "").replace("\\", "/").lstrip("/")
    files = list(oss_storage.iter_local_media_files(root))
    if prefix:
        files = [
            p
            for p in files
            if p.relative_to(root).as_posix().startswith(prefix)
        ]

    total = len(files)
    print(f"media root: {root}")
    print(f"bucket: {settings.oss_bucket} @ {settings.oss_endpoint}")
    print(f"prefix: {settings.oss_key_prefix!r}  filter={prefix!r}")
    print(f"files: {total}  dry_run={args.dry_run}")

    uploaded = skipped = failed = 0
    t0 = time.time()
    for i, path in enumerate(files, start=1):
        rel = path.relative_to(root).as_posix()
        key = oss_storage.object_key_for_relative(rel)
        try:
            if args.skip_existing and oss_storage.object_exists(rel):
                skipped += 1
                if i % 50 == 0 or i == total:
                    print(f"[{i}/{total}] skip {rel}")
                continue
            if args.dry_run:
                uploaded += 1
                if i <= 20 or i % 100 == 0 or i == total:
                    print(f"[{i}/{total}] would upload {rel} → {key}")
                continue
            oss_storage.put_file(rel, path)
            uploaded += 1
            if args.delete_local_after:
                path.unlink(missing_ok=True)
            if i % 25 == 0 or i == total:
                print(f"[{i}/{total}] ok {rel} ({path.stat().st_size} B)")
        except Exception as exc:  # noqa: BLE001
            failed += 1
            print(f"[{i}/{total}] FAIL {rel}: {type(exc).__name__}: {exc}")

    elapsed = time.time() - t0
    print(
        f"DONE uploaded={uploaded} skipped={skipped} failed={failed} "
        f"elapsed={elapsed:.1f}s"
    )
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
