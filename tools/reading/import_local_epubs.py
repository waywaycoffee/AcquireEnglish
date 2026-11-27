"""Import local EPUB novels into an owner's reading library (ECS + backup).

Extracts plain text (same rules as the mobile EPUB importer), stores corpus under
``media/reading/personal/{user_id}/ebooks/{series}/``, writes a series manifest,
and merges ReadingDoc rows into ``reading_library_backups`` so the next App sync
puts them on the shelf.

Does **not** commit EPUB binaries into git. Prefer personal ECS paths over public
catalog seeds for copyrighted personal-learning copies.

Examples::

  python tools/reading/import_local_epubs.py ^
    --series harry-potter ^
    --series-title "哈利·波特（Harry Potter）" ^
    --user-id 1 ^
    --upload ^
    --seed-backup ^
    "D:\\AcquireEnglish\\docs\\书籍\\哈利波特\\*.epub"
"""

from __future__ import annotations

import argparse
import hashlib
import html
import json
import os
import re
import sys
import tempfile
import zipfile
from dataclasses import dataclass
from datetime import datetime, timezone
from html.parser import HTMLParser
from pathlib import Path
from typing import Iterable

_SKIP_NAME_PARTS = (
    "toc",
    "nav",
    "colophon",
    "imprint",
    "uncopyright",
    "titlepage",
    "cover",
    "dedication",
    "halftitle",
    "epigraph",
    "loi",
    "copyright",
)

# Default Harry Potter 1–7 bilingual titles (EN primary, ZH for display).
HP_TITLES: dict[int, tuple[str, str]] = {
    1: ("Harry Potter and the Sorcerer's Stone", "哈利·波特与魔法石"),
    2: ("Harry Potter and the Chamber of Secrets", "哈利·波特与密室"),
    3: ("Harry Potter and the Prisoner of Azkaban", "哈利·波特与阿兹卡班的囚徒"),
    4: ("Harry Potter and the Goblet of Fire", "哈利·波特与火焰杯"),
    5: ("Harry Potter and the Order of the Phoenix", "哈利·波特与凤凰社"),
    6: ("Harry Potter and the Half-Blood Prince", "哈利·波特与混血王子"),
    7: ("Harry Potter and the Deathly Hallows", "哈利·波特与死亡圣器"),
}


class _TextExtractor(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self._chunks: list[str] = []
        self._skip = 0

    def handle_starttag(self, tag: str, attrs) -> None:  # noqa: ANN001
        if tag in {"script", "style"}:
            self._skip += 1

    def handle_endtag(self, tag: str) -> None:
        if tag in {"script", "style"} and self._skip:
            self._skip -= 1
        if tag in {"p", "div", "br", "li", "h1", "h2", "h3", "h4", "tr"}:
            self._chunks.append("\n")

    def handle_data(self, data: str) -> None:
        if self._skip:
            return
        text = data.strip()
        if text:
            self._chunks.append(text)

    def text(self) -> str:
        raw = " ".join(self._chunks)
        return re.sub(r"[ \t]+", " ", raw).strip()


def _natural_key(path: str) -> list:
    parts = re.split(r"(\d+)", path.replace("\\", "/").lower())
    out: list = []
    for p in parts:
        if p.isdigit():
            out.append(int(p))
        else:
            out.append(p)
    return out


def parse_epub_text(epub_path: Path) -> str:
    """Match mobile ``parseEpubImport``: xhtml/html bodies, skip nav/boilerplate."""
    data = epub_path.read_bytes()
    if len(data) < 4 or data[0] != 0x50 or data[1] != 0x4B:
        raise ValueError(f"not a zip/epub: {epub_path}")
    with zipfile.ZipFile(epub_path) as zf:
        names = [
            n
            for n in zf.namelist()
            if n.lower().endswith((".xhtml", ".html", ".htm"))
            and not n.endswith("/")
        ]
        keep: list[str] = []
        for name in names:
            base = name.replace("\\", "/").split("/")[-1].lower()
            if any(part in base for part in _SKIP_NAME_PARTS):
                if base.startswith("toc") or any(
                    p in base
                    for p in (
                        "nav",
                        "colophon",
                        "imprint",
                        "uncopyright",
                        "titlepage",
                        "cover",
                        "dedication",
                        "halftitle",
                        "epigraph",
                        "loi",
                        "copyright",
                    )
                ):
                    continue
            keep.append(name)
        keep.sort(key=_natural_key)
        chunks: list[str] = []
        for name in keep:
            raw = zf.read(name)
            try:
                xml = raw.decode("utf-8")
            except UnicodeDecodeError:
                xml = raw.decode("utf-8", errors="replace")
            # Prefer body text when present.
            m = re.search(r"<body[^>]*>(.*)</body>", xml, re.I | re.S)
            body = m.group(1) if m else xml
            parser = _TextExtractor()
            try:
                parser.feed(body)
                parser.close()
            except Exception:
                plain = re.sub(r"<[^>]+>", " ", body)
                plain = html.unescape(re.sub(r"\s+", " ", plain)).strip()
                if plain:
                    chunks.append(plain)
                continue
            plain = parser.text()
            if plain:
                chunks.append(plain)
    return "\n\n".join(chunks).strip()


def _infer_index(path: Path) -> int | None:
    m = re.match(r"^0*([1-7])\b", path.name)
    if m:
        return int(m.group(1))
    m = re.search(r"(?:harry|potter|hp)\D{0,8}([1-7])\b", path.name, re.I)
    if m:
        return int(m.group(1))
    return None


def word_count(text: str) -> int:
    return len([w for w in re.split(r"\s+", text.strip()) if w])


@dataclass
class BookSpec:
    index: int
    epub_path: Path
    title_en: str
    title_zh: str
    doc_id: str
    slug: str
    plain_text: str

    @property
    def display_title(self) -> str:
        return f"{self.title_en}（{self.title_zh}）"

    @property
    def content_hash(self) -> str:
        return hashlib.sha256(self.plain_text.encode("utf-8")).hexdigest()

    def reading_doc(self, *, series_id: str, series_title: str) -> dict:
        now = datetime.now(timezone.utc).isoformat()
        return {
            "id": self.doc_id,
            "title": self.display_title,
            "titleZh": self.title_zh,
            "sourceType": "import",
            "level": "B2",
            "plainText": self.plain_text,
            "segments": [],
            "courseId": series_id,
            "episodeId": f"{self.index:02d}",
            "courseTitle": series_title,
            "episodeTitle": f"J. K. Rowling · Book {self.index}",
            "sourceLabel": "本地 EPUB 导入",
            "coverUrl": "",
            "createdAt": now,
            "builtin": False,
            "contentHash": self.content_hash,
            "netdiskPath": "",
        }

    def meta(self, *, series_id: str, series_title: str) -> dict:
        return {
            "doc_id": self.doc_id,
            "index": self.index,
            "slug": self.slug,
            "title": self.title_en,
            "title_zh": self.title_zh,
            "display_title": self.display_title,
            "author": "J. K. Rowling",
            "series_id": series_id,
            "series_title": series_title,
            "word_count": word_count(self.plain_text),
            "content_hash": self.content_hash,
            "source_epub": self.epub_path.name,
            "format": "plain_text",
        }


def expand_inputs(patterns: Iterable[str]) -> list[Path]:
    out: list[Path] = []
    for pat in patterns:
        p = Path(pat)
        if any(ch in pat for ch in "*?[]"):
            parent = p.parent if str(p.parent) not in ("", ".") else Path.cwd()
            matches = sorted(parent.glob(p.name))
            if not matches:
                raise FileNotFoundError(pat)
            out.extend(matches)
        elif p.is_file():
            out.append(p)
        else:
            raise FileNotFoundError(pat)
    seen: set[str] = set()
    unique: list[Path] = []
    for path in out:
        key = str(path.resolve())
        if key in seen:
            continue
        seen.add(key)
        unique.append(path.resolve())
    return unique


def build_books(paths: list[Path], series: str) -> list[BookSpec]:
    books: list[BookSpec] = []
    used_idx: set[int] = set()
    for path in paths:
        idx = _infer_index(path)
        if idx is None:
            raise SystemExit(f"cannot infer book index 1–7 from: {path.name}")
        if idx in used_idx:
            raise SystemExit(f"duplicate book index {idx}: {path.name}")
        used_idx.add(idx)
        title_en, title_zh = HP_TITLES.get(idx, (path.stem, f"第{idx}册"))
        print(f"extracting [{idx}] {path.name} …", flush=True)
        text = parse_epub_text(path)
        if len(text) < 500:
            raise SystemExit(f"extracted text too short ({len(text)} chars): {path}")
        slug = f"{idx:02d}-{re.sub(r'[^a-z0-9]+', '-', title_en.lower()).strip('-')}"
        doc_id = f"ebook-{series}-{idx:02d}"
        books.append(
            BookSpec(
                index=idx,
                epub_path=path,
                title_en=title_en,
                title_zh=title_zh,
                doc_id=doc_id,
                slug=slug,
                plain_text=text,
            )
        )
        print(
            f"  -> {word_count(text)} words, {len(text)} chars, id={doc_id}",
            flush=True,
        )
    return sorted(books, key=lambda b: b.index)


def write_local_package(
    books: list[BookSpec],
    *,
    out_dir: Path,
    series_id: str,
    series_title: str,
) -> Path:
    series_dir = out_dir / series_id
    series_dir.mkdir(parents=True, exist_ok=True)
    items = []
    for book in books:
        book_dir = series_dir / f"{book.index:02d}"
        book_dir.mkdir(parents=True, exist_ok=True)
        (book_dir / "book.txt").write_text(book.plain_text, encoding="utf-8")
        meta = book.meta(series_id=series_id, series_title=series_title)
        (book_dir / "meta.json").write_text(
            json.dumps(meta, ensure_ascii=False, indent=2), encoding="utf-8"
        )
        items.append(
            {
                **meta,
                "rel_text": f"{book.index:02d}/book.txt",
                "rel_meta": f"{book.index:02d}/meta.json",
            }
        )
    manifest = {
        "series_id": series_id,
        "series_title": series_title,
        "author": "J. K. Rowling",
        "count": len(items),
        "books": items,
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "note": "Personal-learning EPUB text corpus. Not bundled into the APK.",
    }
    (series_dir / "series.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    return series_dir


def scp_to_ecs(local_series: Path, remote_dir: str, ssh_host: str) -> None:
    import subprocess

    # Ensure remote parent exists, then sync contents.
    subprocess.run(
        ["ssh", ssh_host, f"mkdir -p {remote_dir}"],
        check=True,
    )
    # Upload whole series folder
    subprocess.run(
        ["scp", "-r", str(local_series), f"{ssh_host}:{Path(remote_dir).parent.as_posix()}"],
        check=True,
    )


def seed_reading_backup(
    books: list[BookSpec],
    *,
    user_id: int,
    series_id: str,
    series_title: str,
    ssh_host: str,
) -> dict:
    """Merge docs into reading_library_backups on ECS via a remote Python snippet."""
    import subprocess

    docs = [b.reading_doc(series_id=series_id, series_title=series_title) for b in books]
    payload = {
        "user_id": user_id,
        "docs": docs,
        "series_id": series_id,
    }
    with tempfile.NamedTemporaryFile(
        "w", encoding="utf-8", suffix=".json", delete=False
    ) as tmp:
        json.dump(payload, tmp, ensure_ascii=False)
        tmp_path = tmp.name

    remote_json = f"/tmp/hp_reading_seed_{user_id}.json"
    remote_py = "/tmp/hp_reading_seed.py"
    seed_py = r'''
import asyncio, json, os, sys, hashlib
from pathlib import Path

payload = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
user_id = int(payload["user_id"])
new_docs = payload["docs"]
series_id = payload["series_id"]

for line in Path("/opt/acquireenglish/services/api/.env").read_text(encoding="utf-8").splitlines():
    line = line.strip()
    if not line or line.startswith("#") or "=" not in line:
        continue
    k, v = line.split("=", 1)
    os.environ.setdefault(k.strip(), v.strip().strip('"').strip("'"))

from sqlalchemy import text
from sqlalchemy.ext.asyncio import create_async_engine

url = os.environ["DATABASE_URL"]
if url.startswith("postgresql://"):
    url = url.replace("postgresql://", "postgresql+asyncpg://", 1)
engine = create_async_engine(url)
MAX_BYTES = 16 * 1024 * 1024

async def main():
    async with engine.begin() as conn:
        row = (await conn.execute(
            text("select revision, payload from reading_library_backups where user_id=:u"),
            {"u": user_id},
        )).first()
        if row is None:
            state = {"version": 1, "docs": [], "progress": {}, "vocabLists": {}}
            revision = 0
        else:
            revision = int(row[0])
            state = json.loads(row[1])
            if not isinstance(state, dict):
                state = {"version": 1, "docs": [], "progress": {}, "vocabLists": {}}
        docs = list(state.get("docs") or [])
        by_id = {str(d.get("id")): i for i, d in enumerate(docs) if isinstance(d, dict)}
        upserted = []
        for doc in new_docs:
            did = str(doc["id"])
            if did in by_id:
                docs[by_id[did]] = doc
            else:
                docs.append(doc)
            upserted.append(did)
        state["docs"] = docs
        state["version"] = 1
        encoded = json.dumps(state, ensure_ascii=False, separators=(",", ":"))
        if len(encoded.encode("utf-8")) > MAX_BYTES:
            while len(encoded.encode("utf-8")) > MAX_BYTES:
                largest_i = -1
                largest_n = 0
                for i, d in enumerate(docs):
                    if not isinstance(d, dict):
                        continue
                    if str(d.get("id")) in upserted:
                        continue
                    n = len(str(d.get("plainText") or ""))
                    if n > largest_n:
                        largest_n = n
                        largest_i = i
                if largest_i < 0 or largest_n == 0:
                    break
                d = dict(docs[largest_i])
                body = str(d.get("plainText") or "")
                if body and not d.get("contentHash"):
                    d["contentHash"] = hashlib.sha256(body.encode("utf-8")).hexdigest()
                d["plainText"] = ""
                d["segments"] = []
                docs[largest_i] = d
                state["docs"] = docs
                encoded = json.dumps(state, ensure_ascii=False, separators=(",", ":"))
        nbytes = len(encoded.encode("utf-8"))
        if nbytes > MAX_BYTES:
            raise SystemExit(f"backup still too large after shrink: {nbytes}")
        next_rev = revision + 1
        if revision == 0:
            await conn.execute(
                text(
                    "insert into reading_library_backups (user_id, revision, payload) "
                    "values (:u, :r, :p)"
                ),
                {"u": user_id, "r": next_rev, "p": encoded},
            )
        else:
            res = await conn.execute(
                text(
                    "update reading_library_backups set revision=:r, payload=:p "
                    "where user_id=:u and revision=:old"
                ),
                {"u": user_id, "r": next_rev, "p": encoded, "old": revision},
            )
            if res.rowcount != 1:
                raise SystemExit("revision conflict; retry")
        print(json.dumps({
            "user_id": user_id,
            "revision": next_rev,
            "bytes": nbytes,
            "upserted": upserted,
            "doc_count": len(docs),
            "series_id": series_id,
        }, ensure_ascii=False))

asyncio.run(main())
'''
    local_py = tempfile.NamedTemporaryFile(
        "w", encoding="utf-8", suffix=".py", delete=False
    )
    local_py.write(seed_py)
    local_py.close()
    local_py_path = local_py.name

    try:
        subprocess.run(["scp", tmp_path, f"{ssh_host}:{remote_json}"], check=True)
        subprocess.run(["scp", local_py_path, f"{ssh_host}:{remote_py}"], check=True)
        proc = subprocess.run(
            [
                "ssh",
                ssh_host,
                "cd /opt/acquireenglish/services/api && . .venv/bin/activate "
                f"&& python {remote_py} {remote_json}",
            ],
            check=True,
            capture_output=True,
            text=True,
        )
    except subprocess.CalledProcessError as exc:
        err = (exc.stderr or "") + "\n" + (exc.stdout or "")
        raise SystemExit(f"seed-backup failed:\n{err}") from exc
    finally:
        Path(tmp_path).unlink(missing_ok=True)
        Path(local_py_path).unlink(missing_ok=True)

    line = (proc.stdout or "").strip().splitlines()[-1]
    return json.loads(line)


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("epubs", nargs="+", help="EPUB paths or globs")
    ap.add_argument("--series", default="harry-potter")
    ap.add_argument("--series-title", default="哈利·波特（Harry Potter）")
    ap.add_argument("--user-id", type=int, default=1, help="Owner user_id (weiwei=1)")
    ap.add_argument("--ssh-host", default="acquireenglish")
    ap.add_argument(
        "--work-dir",
        default="",
        help="Local package dir (default: tmp/reading_ebooks/<series>)",
    )
    ap.add_argument("--upload", action="store_true", help="scp package to ECS personal ebooks")
    ap.add_argument(
        "--seed-backup",
        action="store_true",
        help="Merge ReadingDocs into reading_library_backups",
    )
    ap.add_argument(
        "--keep-epub",
        action="store_true",
        help="Also copy source EPUB next to book.txt on ECS (private personal path)",
    )
    args = ap.parse_args(argv)

    paths = expand_inputs(args.epubs)
    if not paths:
        raise SystemExit("no EPUB files matched")
    print(f"matched {len(paths)} EPUB(s)", flush=True)

    books = build_books(paths, args.series)
    work = Path(args.work_dir) if args.work_dir else Path("tmp/reading_ebooks")
    series_dir = write_local_package(
        books,
        out_dir=work,
        series_id=args.series,
        series_title=args.series_title,
    )
    if args.keep_epub:
        for book in books:
            dest = series_dir / f"{book.index:02d}" / book.epub_path.name
            dest.write_bytes(book.epub_path.read_bytes())

    print(f"local package: {series_dir}", flush=True)
    remote_parent = (
        f"/opt/acquireenglish/services/api/media/reading/personal/"
        f"{args.user_id}/ebooks"
    )
    remote_series = f"{remote_parent}/{args.series}"

    result = {
        "series_id": args.series,
        "series_title": args.series_title,
        "user_id": args.user_id,
        "local_package": str(series_dir.resolve()),
        "ecs_path": remote_series if args.upload else None,
        "books": [
            {
                "index": b.index,
                "doc_id": b.doc_id,
                "title": b.display_title,
                "words": word_count(b.plain_text),
                "chars": len(b.plain_text),
                "content_hash": b.content_hash[:16],
            }
            for b in books
        ],
    }

    if args.upload:
        print(f"uploading to {args.ssh_host}:{remote_series} …", flush=True)
        scp_to_ecs(series_dir, remote_series, args.ssh_host)
        print("upload ok", flush=True)

    if args.seed_backup:
        print(f"seeding reading-backup for user {args.user_id} …", flush=True)
        seed = seed_reading_backup(
            books,
            user_id=args.user_id,
            series_id=args.series,
            series_title=args.series_title,
            ssh_host=args.ssh_host,
        )
        result["backup"] = seed
        print(json.dumps(seed, ensure_ascii=False, indent=2), flush=True)

    summary_path = series_dir / "import_result.json"
    # Never write full plainText into the summary.
    summary_path.write_text(
        json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    print(json.dumps(result, ensure_ascii=False, indent=2), flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
