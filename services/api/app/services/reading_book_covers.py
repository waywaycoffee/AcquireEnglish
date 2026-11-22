"""Resolve classic book covers via Open Library and cache on ECS.

Files land under ``{media_cache_dir}/reading/covers/{key}.jpg`` and are
served as ``/media/reading/covers/...`` (never bundled into the APK).
"""
from __future__ import annotations

import hashlib
import json
import re
import time
from pathlib import Path
from typing import Any

import httpx

from app.services import content_media as cm

OPENLIBRARY_SEARCH = "https://openlibrary.org/search.json"
OPENLIBRARY_COVER = "https://covers.openlibrary.org/b/id/{cover_id}-L.jpg"
USER_AGENT = "AcquireEnglish-ReadingCovers/1.0 (educational; contact=acquireenglish)"
_TITLE_PAREN = re.compile(r"[\(（][^\)）]*[\)）]")
_SAFE = re.compile(r"[^a-z0-9]+")


def _covers_root() -> Path:
    root = cm.namespace_root("reading") / "covers"
    root.mkdir(parents=True, exist_ok=True)
    return root


def _index_path() -> Path:
    return _covers_root() / "index.json"


def _load_index() -> dict[str, Any]:
    path = _index_path()
    if not path.is_file():
        return {}
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {}
    return data if isinstance(data, dict) else {}


def _save_index(index: dict[str, Any]) -> None:
    path = _index_path()
    tmp = path.with_suffix(".tmp")
    tmp.write_text(json.dumps(index, ensure_ascii=False, indent=2), encoding="utf-8")
    tmp.replace(path)


def normalize_title(title: str) -> str:
    """Strip bilingual display wrappers for Open Library search."""
    text = (title or "").strip()
    text = _TITLE_PAREN.sub("", text)
    text = text.replace("’", "'").replace("‘", "'").replace("ʼ", "'")
    text = re.sub(r"\s+", " ", text).strip(" -–—")
    return text


def cover_key(*, title: str, author: str = "", doc_id: str = "") -> str:
    # Title-only key so shelf docs (with/without author) share one ECS file.
    del author, doc_id
    raw = f"t:{normalize_title(title).lower()}"
    digest = hashlib.sha1(raw.encode("utf-8")).hexdigest()[:20]
    return digest


def _cached_entry(key: str) -> dict[str, Any] | None:
    index = _load_index()
    entry = index.get(key)
    if not isinstance(entry, dict):
        return None
    rel = str(entry.get("relative") or "")
    if not rel:
        return None
    path = cm.namespace_root("reading") / rel
    if not path.is_file() or path.stat().st_size < 256:
        return None
    return {
        "key": key,
        "cover_url": cm.public_url("reading", rel),
        "relative": rel,
        "source": entry.get("source") or "cache",
        "title": entry.get("title") or "",
        "author": entry.get("author") or "",
        "doc_id": entry.get("doc_id"),
        "cached": True,
        "cover_id": entry.get("cover_id"),
    }


async def _search_openlibrary(title: str, author: str) -> dict[str, Any] | None:
    q_title = normalize_title(title)
    if not q_title:
        return None
    params: dict[str, str | int] = {
        "title": q_title,
        "fields": "key,title,author_name,cover_i,first_publish_year,edition_count",
        "limit": 8,
    }
    if (author or "").strip():
        params["author"] = author.strip()
    async with httpx.AsyncClient(
        timeout=25.0,
        follow_redirects=True,
        verify=False,
        headers={"User-Agent": USER_AGENT, "Accept": "application/json"},
    ) as client:
        resp = await client.get(OPENLIBRARY_SEARCH, params=params)
        resp.raise_for_status()
        payload = resp.json()
        docs = payload.get("docs") if isinstance(payload, dict) else None
        if not isinstance(docs, list) or not docs:
            # Retry without author if author filter was too strict.
            if "author" in params:
                params.pop("author")
                resp = await client.get(OPENLIBRARY_SEARCH, params=params)
                resp.raise_for_status()
                payload = resp.json()
                docs = payload.get("docs") if isinstance(payload, dict) else None
        if not isinstance(docs, list):
            return None
        q_lower = q_title.lower()
        ranked: list[tuple[int, dict[str, Any]]] = []
        for doc in docs:
            if not isinstance(doc, dict):
                continue
            cover_i = doc.get("cover_i")
            if not cover_i:
                continue
            hit_title = str(doc.get("title") or "").strip()
            score = 0
            if hit_title.lower() == q_lower:
                score += 100
            elif q_lower in hit_title.lower() or hit_title.lower() in q_lower:
                score += 40
            authors = doc.get("author_name") or []
            if author and isinstance(authors, list):
                a = author.lower()
                if any(a in str(x).lower() or str(x).lower() in a for x in authors):
                    score += 30
            score += min(int(doc.get("edition_count") or 0), 20)
            ranked.append((score, doc))
        if not ranked:
            return None
        ranked.sort(key=lambda item: item[0], reverse=True)
        best = ranked[0][1]
        return {
            "cover_id": int(best["cover_i"]),
            "title": str(best.get("title") or q_title),
            "authors": list(best.get("author_name") or []),
            "ol_key": str(best.get("key") or ""),
        }


async def _download_cover(cover_id: int, dest: Path) -> bool:
    url = OPENLIBRARY_COVER.format(cover_id=cover_id) + "?default=false"
    async with httpx.AsyncClient(
        timeout=40.0,
        follow_redirects=True,
        verify=False,
        headers={"User-Agent": USER_AGENT, "Accept": "image/*"},
    ) as client:
        resp = await client.get(url)
        if resp.status_code == 404:
            return False
        resp.raise_for_status()
        data = resp.content
        if len(data) < 256:
            return False
        ctype = (resp.headers.get("content-type") or "").lower()
        if "image" not in ctype and not data[:3] in (b"\xff\xd8\xff", b"\x89PN"):
            # Still accept if it looks like JPEG/PNG magic.
            if data[:3] != b"\xff\xd8\xff" and data[:4] != b"\x89PNG":
                return False
        dest.parent.mkdir(parents=True, exist_ok=True)
        tmp = dest.with_suffix(dest.suffix + ".tmp")
        tmp.write_bytes(data)
        tmp.replace(dest)
        return True


async def resolve_cover(
    *,
    title: str,
    author: str = "",
    doc_id: str = "",
    force: bool = False,
) -> dict[str, Any]:
    """Return a public cover URL, searching Open Library on cache miss."""
    key = cover_key(title=title, author=author, doc_id=doc_id)
    if not force:
        hit = _cached_entry(key)
        if hit is not None:
            if (doc_id or "").strip() and not hit.get("doc_id"):
                hit = {**hit, "doc_id": doc_id.strip()}
            elif (doc_id or "").strip():
                hit = {**hit, "doc_id": doc_id.strip()}
            return hit

    clean_title = normalize_title(title)
    if not clean_title:
        return {
            "key": key,
            "cover_url": None,
            "cached": False,
            "source": "none",
            "message": "empty_title",
        }

    try:
        match = await _search_openlibrary(clean_title, author)
    except Exception as exc:  # noqa: BLE001
        return {
            "key": key,
            "cover_url": None,
            "cached": False,
            "source": "openlibrary",
            "error": str(exc)[:240],
            "message": "search_failed",
        }
    if match is None:
        return {
            "key": key,
            "cover_url": None,
            "cached": False,
            "source": "openlibrary",
            "message": "not_found",
            "title": clean_title,
            "author": author,
        }

    rel = f"covers/{key}.jpg"
    dest = cm.namespace_root("reading") / rel
    try:
        ok = await _download_cover(int(match["cover_id"]), dest)
    except Exception as exc:  # noqa: BLE001
        return {
            "key": key,
            "cover_url": None,
            "cached": False,
            "source": "openlibrary",
            "error": str(exc)[:240],
            "message": "download_failed",
            "cover_id": match["cover_id"],
        }
    if not ok:
        return {
            "key": key,
            "cover_url": None,
            "cached": False,
            "source": "openlibrary",
            "message": "download_empty",
            "cover_id": match["cover_id"],
        }

    index = _load_index()
    index[key] = {
        "relative": rel,
        "title": clean_title,
        "author": (author or "").strip(),
        "source": "openlibrary",
        "cover_id": match["cover_id"],
        "ol_key": match.get("ol_key") or "",
        "updated": time.time(),
        "doc_id": (doc_id or "").strip() or None,
    }
    _save_index(index)
    return {
        "key": key,
        "cover_url": cm.public_url("reading", rel),
        "relative": rel,
        "source": "openlibrary",
        "cached": False,
        "title": clean_title,
        "author": (author or "").strip(),
        "doc_id": (doc_id or "").strip() or None,
        "cover_id": match["cover_id"],
        "message": "ok",
    }


async def ensure_covers(books: list[dict[str, Any]]) -> dict[str, Any]:
    """Resolve a batch of books (serial; Open Library rate limits)."""
    results: list[dict[str, Any]] = []
    for item in books:
        if not isinstance(item, dict):
            continue
        title = str(item.get("title") or "").strip()
        if not title:
            continue
        result = await resolve_cover(
            title=title,
            author=str(item.get("author") or "").strip(),
            doc_id=str(item.get("doc_id") or item.get("id") or "").strip(),
            force=bool(item.get("force")),
        )
        results.append(result)
        # Be polite to Open Library when filling misses.
        if not result.get("cached") and result.get("message") == "ok":
            import asyncio

            await asyncio.sleep(0.35)
    found = sum(1 for r in results if r.get("cover_url"))
    return {"count": len(results), "found": found, "covers": results}


# Featured Standard Ebooks classics (keep in sync with App kStandardEbooksFeatured).
FEATURED_CLASSICS: list[dict[str, str]] = [
    {
        "doc_id": "se:l-frank-baum/the-wonderful-wizard-of-oz",
        "title": "The Wonderful Wizard of Oz",
        "author": "L. Frank Baum",
    },
    {
        "doc_id": "se:jane-austen/pride-and-prejudice",
        "title": "Pride and Prejudice",
        "author": "Jane Austen",
    },
    {
        "doc_id": "se:mary-shelley/frankenstein",
        "title": "Frankenstein",
        "author": "Mary Shelley",
    },
    {
        "doc_id": "se:bram-stoker/dracula",
        "title": "Dracula",
        "author": "Bram Stoker",
    },
    {
        "doc_id": "se:lewis-carroll/alices-adventures-in-wonderland",
        "title": "Alice's Adventures in Wonderland",
        "author": "Lewis Carroll",
    },
    {
        "doc_id": "se:arthur-conan-doyle/the-adventures-of-sherlock-holmes",
        "title": "The Adventures of Sherlock Holmes",
        "author": "Arthur Conan Doyle",
    },
    {
        "doc_id": "se:charles-dickens/a-christmas-carol",
        "title": "A Christmas Carol",
        "author": "Charles Dickens",
    },
    {
        "doc_id": "se:robert-louis-stevenson/treasure-island",
        "title": "Treasure Island",
        "author": "Robert Louis Stevenson",
    },
    {
        "doc_id": "se:jonathan-swift/gullivers-travels",
        "title": "Gulliver's Travels",
        "author": "Jonathan Swift",
    },
    {
        "doc_id": "se:mark-twain/the-adventures-of-huckleberry-finn",
        "title": "Adventures of Huckleberry Finn",
        "author": "Mark Twain",
    },
    {
        "doc_id": "se:herman-melville/moby-dick",
        "title": "Moby Dick",
        "author": "Herman Melville",
    },
]
