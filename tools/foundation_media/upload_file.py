#!/usr/bin/env python3
"""Upload one foundation audio/video file to AcquireEnglish API."""

from __future__ import annotations

import argparse
import mimetypes
import sys
from pathlib import Path

import urllib.request


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base", required=True, help="API base, e.g. https://host")
    parser.add_argument("--token", required=True, help="Bearer access token")
    parser.add_argument("--book", required=True, help="book_id, e.g. foundation_ipa_48")
    parser.add_argument("--key", required=True, help="item key matching syllabus word")
    parser.add_argument("--file", required=True, type=Path, help="local media file")
    args = parser.parse_args()

    path: Path = args.file
    if not path.is_file():
        print(f"missing file: {path}", file=sys.stderr)
        return 2

    boundary = "----AcquireFoundationMediaBoundary"
    mime = mimetypes.guess_type(path.name)[0] or "application/octet-stream"
    data = path.read_bytes()

    def part(name: str, value: bytes, filename: str | None = None, content_type: str | None = None) -> bytes:
        disposition = f'Content-Disposition: form-data; name="{name}"'
        if filename is not None:
            disposition += f'; filename="{filename}"'
        headers = disposition.encode() + b"\r\n"
        if content_type:
            headers += f"Content-Type: {content_type}\r\n".encode()
        return b"--" + boundary.encode() + b"\r\n" + headers + b"\r\n" + value + b"\r\n"

    body = b"".join(
        [
            part("book_id", args.book.encode()),
            part("key", args.key.encode()),
            part("file", data, filename=path.name, content_type=mime),
            b"--" + boundary.encode() + b"--\r\n",
        ]
    )

    url = args.base.rstrip("/") + "/api/foundation/media/upload"
    req = urllib.request.Request(
        url,
        data=body,
        method="POST",
        headers={
            "Authorization": f"Bearer {args.token}",
            "Content-Type": f"multipart/form-data; boundary={boundary}",
        },
    )
    with urllib.request.urlopen(req, timeout=120) as resp:
        print(resp.read().decode("utf-8", errors="replace"))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
