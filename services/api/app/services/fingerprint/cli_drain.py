"""CLI: drain fingerprint upload_task queue_gpu once.

Usage (from services/api with venv):

    python -m app.services.fingerprint.cli_drain
    python -m app.services.fingerprint.cli_drain --limit 10
"""

from __future__ import annotations

import argparse
import asyncio
import json


async def _main(limit: int) -> None:
    from app.services.fingerprint.queue_worker import drain_once

    results = await drain_once(limit=limit)
    print(json.dumps({"processed": len(results), "results": results}, ensure_ascii=False, indent=2))


def main() -> None:
    parser = argparse.ArgumentParser(description="Drain fingerprint queue_gpu tasks")
    parser.add_argument("--limit", type=int, default=5)
    args = parser.parse_args()
    asyncio.run(_main(args.limit))


if __name__ == "__main__":
    main()
