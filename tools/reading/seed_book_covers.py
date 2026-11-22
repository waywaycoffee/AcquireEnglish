"""Fetch classic book covers on this PC (Open Library) and upload to ECS.

Guangzhou ECS often cannot reach openlibrary.org; this developer box can.

  python tools/reading/seed_book_covers.py --upload
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import ssl
import subprocess
import time
import urllib.parse
import urllib.request
from pathlib import Path

# Corporate MITM / incomplete CA store on some Windows boxes.
_SSL = ssl.create_default_context()
_SSL.check_hostname = False
_SSL.verify_mode = ssl.CERT_NONE

USER_AGENT = "AcquireEnglish-ReadingCovers/1.0"
TITLE_PAREN = re.compile(r"[\(（][^\)）]*[\)）]")
PUBLIC_BASE = "https://acquireenglish.curlhairai.com"

FEATURED = [
    {"doc_id": "se:l-frank-baum/the-wonderful-wizard-of-oz", "title": "The Wonderful Wizard of Oz", "author": "L. Frank Baum"},
    {"doc_id": "se:jane-austen/pride-and-prejudice", "title": "Pride and Prejudice", "author": "Jane Austen"},
    {"doc_id": "se:mary-shelley/frankenstein", "title": "Frankenstein", "author": "Mary Shelley"},
    {"doc_id": "se:bram-stoker/dracula", "title": "Dracula", "author": "Bram Stoker"},
    {"doc_id": "se:lewis-carroll/alices-adventures-in-wonderland", "title": "Alice's Adventures in Wonderland", "author": "Lewis Carroll"},
    {"doc_id": "se:arthur-conan-doyle/the-adventures-of-sherlock-holmes", "title": "The Adventures of Sherlock Holmes", "author": "Arthur Conan Doyle"},
    {"doc_id": "se:charles-dickens/a-christmas-carol", "title": "A Christmas Carol", "author": "Charles Dickens"},
    {"doc_id": "se:robert-louis-stevenson/treasure-island", "title": "Treasure Island", "author": "Robert Louis Stevenson"},
    {"doc_id": "se:jonathan-swift/gullivers-travels", "title": "Gulliver's Travels", "author": "Jonathan Swift"},
    {"doc_id": "se:mark-twain/the-adventures-of-huckleberry-finn", "title": "Adventures of Huckleberry Finn", "author": "Mark Twain"},
    {"doc_id": "se:herman-melville/moby-dick", "title": "Moby Dick", "author": "Herman Melville"},
]


def normalize_title(title: str) -> str:
    text = (title or "").strip()
    text = TITLE_PAREN.sub("", text)
    text = (
        text.replace("\u2019", "'")
        .replace("\u2018", "'")
        .replace("\u02bc", "'")
    )
    text = re.sub(r"\s+", " ", text).strip(" -–—")
    return text


def cover_key(title: str) -> str:
    raw = f"t:{normalize_title(title).lower()}"
    return hashlib.sha1(raw.encode("utf-8")).hexdigest()[:20]


def http_json(url: str, timeout: float = 30) -> dict:
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT, "Accept": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout, context=_SSL) as resp:
        return json.loads(resp.read().decode("utf-8"))


def http_bytes(url: str, timeout: float = 40) -> bytes:
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT, "Accept": "image/*"})
    with urllib.request.urlopen(req, timeout=timeout, context=_SSL) as resp:
        return resp.read()


def search_cover(title: str, author: str) -> int | None:
    q = normalize_title(title)
    params = urllib.parse.urlencode(
        {
            "title": q,
            "author": author,
            "fields": "title,author_name,cover_i,edition_count",
            "limit": 8,
        }
    )
    data = http_json(f"https://openlibrary.org/search.json?{params}")
    docs = data.get("docs") or []
    if not docs and author:
        params = urllib.parse.urlencode(
            {"title": q, "fields": "title,cover_i,edition_count", "limit": 8}
        )
        data = http_json(f"https://openlibrary.org/search.json?{params}")
        docs = data.get("docs") or []
    best = None
    best_score = -1
    q_lower = q.lower()
    for doc in docs:
        cover_i = doc.get("cover_i")
        if not cover_i:
            continue
        hit = str(doc.get("title") or "").lower()
        score = 0
        if hit == q_lower:
            score += 100
        elif q_lower in hit or hit in q_lower:
            score += 40
        score += min(int(doc.get("edition_count") or 0), 20)
        if score > best_score:
            best_score = score
            best = int(cover_i)
    return best


def seed(out_dir: Path) -> dict:
    covers_dir = out_dir / "reading" / "covers"
    covers_dir.mkdir(parents=True, exist_ok=True)
    index: dict = {}
    results = []
    for book in FEATURED:
        title = book["title"]
        author = book["author"]
        key = cover_key(title)
        rel = f"covers/{key}.jpg"
        dest = covers_dir / f"{key}.jpg"
        try:
            cover_id = search_cover(title, author)
            if cover_id is None:
                results.append({"title": title, "message": "not_found"})
                continue
            data = http_bytes(
                f"https://covers.openlibrary.org/b/id/{cover_id}-L.jpg?default=false"
            )
            if len(data) < 256:
                results.append({"title": title, "message": "empty"})
                continue
            dest.write_bytes(data)
            entry = {
                "relative": rel,
                "title": normalize_title(title),
                "author": author,
                "source": "openlibrary",
                "cover_id": cover_id,
                "updated": time.time(),
                "doc_id": book["doc_id"],
            }
            index[key] = entry
            results.append(
                {
                    "title": title,
                    "message": "ok",
                    "cover_url": f"{PUBLIC_BASE}/media/reading/{rel}",
                    "bytes": len(data),
                    "doc_id": book["doc_id"],
                }
            )
            print("ok", title, cover_id, len(data))
            time.sleep(0.35)
        except Exception as exc:  # noqa: BLE001
            results.append({"title": title, "message": "error", "error": str(exc)[:200]})
            print("fail", title, exc)
    (covers_dir / "index.json").write_text(
        json.dumps(index, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    found = sum(1 for r in results if r.get("message") == "ok")
    return {"count": len(results), "found": found, "covers": results}


def upload(out_dir: Path, host: str) -> None:
    covers_dir = out_dir / "reading" / "covers"
    remote = "/opt/acquireenglish/services/api/media/reading/covers"
    subprocess.run(["ssh", host, f"mkdir -p {remote}"], check=True)
    for path in sorted(covers_dir.iterdir()):
        if path.suffix.lower() not in {".jpg", ".jpeg", ".png", ".json"}:
            continue
        subprocess.run(["scp", str(path), f"{host}:{remote}/{path.name}"], check=True)
        print("uploaded", path.name)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--upload", action="store_true")
    parser.add_argument("--host", default="acquireenglish")
    parser.add_argument("--out", default=str(Path(".tmp_covers_media")))
    args = parser.parse_args()
    out = Path(args.out)
    result = seed(out)
    print(json.dumps({"count": result["count"], "found": result["found"]}, indent=2))
    if args.upload:
        upload(out, args.host)
        print("uploaded to ECS")
    return 0 if result["found"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
