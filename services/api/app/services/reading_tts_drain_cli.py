"""Detached CLI: drain unfinished reading TTS pages for one book voice.

Used instead of FastAPI BackgroundTasks so uvicorn can restart cleanly while
CosyVoice fills long novels.

  cd /opt/acquireenglish/services/api
  .venv/bin/python -m app.services.reading_tts_drain_cli \\
      --doc-id catalog_xxx --voice longanfengyue
"""
from __future__ import annotations

import argparse
import asyncio
import sys


async def _run(doc_id: str, voice: str, user_id: int | None) -> None:
    # Local import keeps module import light for -m startup.
    from app.routers.reading_speech import drain_book_pregen_ecs
    from app.services import reading_tts_queue as rtq

    before = rtq.book_status(doc_id=doc_id, voice=voice)
    print(
        f"drain start doc={doc_id} voice={voice} "
        f"{before.get('pages_ready')}/{before.get('pages_total')} "
        f"{before.get('percent')}%",
        flush=True,
    )
    await drain_book_pregen_ecs(doc_id=doc_id, voice=voice, user_id=user_id)
    after = rtq.book_status(doc_id=doc_id, voice=voice)
    print(
        f"drain done doc={doc_id} voice={voice} "
        f"{after.get('pages_ready')}/{after.get('pages_total')} "
        f"{after.get('percent')}%",
        flush=True,
    )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--doc-id", required=True)
    parser.add_argument("--voice", required=True)
    parser.add_argument("--user-id", type=int, default=None)
    args = parser.parse_args(argv)
    asyncio.run(_run(args.doc_id.strip(), args.voice.strip(), args.user_id))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
