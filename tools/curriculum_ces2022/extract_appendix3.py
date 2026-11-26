#!/usr/bin/env python3
"""Extract CES2022 Appendix 3 vocabulary (level2 / level3) from the official PDF.

The PDF is scan-only (no text layer). This script OCRs appendix pages only
(two-column crop + RapidOCR), cleans surfaces, and writes CSVs + manifest.

Usage:
  python tools/curriculum_ces2022/extract_appendix3.py ^
    --pdf "C:\\Users\\Administrator\\Downloads\\《义务教育英语课程标准（2022 版）》.pdf"
"""

from __future__ import annotations

import argparse
import csv
import json
import re
import sqlite3
import sys
from datetime import datetime, timezone
from pathlib import Path

import numpy as np
from PIL import Image, ImageEnhance

try:
    import pymupdf
except ImportError:  # pragma: no cover
    import fitz as pymupdf  # type: ignore

from rapidocr_onnxruntime import RapidOCR

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_OUT = ROOT / "services" / "api" / "data" / "curriculum" / "ces2022"
DEFAULT_TMP = ROOT / "tmp" / "ces2022"
LEXICON_PATH = ROOT / "services" / "api" / "public-lexicon.sqlite3"

# Printed page 87–137 ≈ PDF indices below (cover/front-matter offset = +7).
PDF_LEVEL2_INTRO = 93  # 0-based: PDF page 94
PDF_LEVEL2_WORDS = range(94, 104)  # PDF 95–104
PDF_LEVEL3_INTRO = 104  # PDF 105
# Main alphabetical list only (stop before 数词表 on PDF 135).
PDF_LEVEL3_WORDS = range(105, 135)  # PDF 106–135
PDF_IRREGULAR = 139
# Chinese section headers (incl. common OCR garble like 数话≈数词表).
STOP_MARKERS = (
    "数词表",
    "数词",
    "数话",
    "基数词",
    "序数词",
    "月份",
    "星期词汇",
    "地理名称",
    "名称缩写",
    "不规则动词",
)
OCR_JUNK_LEMMAS = frozenset(
    {
        "woity",
        "nan",
        "vall",
        "peq",
        "paq",
        "ppe",
        "mi",
        "exa",
        "fia",
        "j",
    }
)

LETTER_ONLY = re.compile(r"^[A-Z]$")
PAGE_NUM = re.compile(r"^\d{1,3}$")
NOISE_CN = re.compile(r"[\u4e00-\u9fff]")
# Primary surface: letters / apostrophe / hyphen, optional parenthetical or slash forms.
SURFACE_OK = re.compile(
    r"^[A-Za-z][A-Za-z''\-/]*(?:\s*/\s*[A-Za-z][A-Za-z''\-/]*)?"
    r"(?:\s*\([^)]*\))?$"
)
PRIMARY_FORM = re.compile(r"^([A-Za-z][A-Za-z''\-]*)")

# OCR upside-down latin remapping (empirical for this PDF font).
_UPSIDE = str.maketrans(
    {
        "p": "d",
        "q": "b",
        "b": "q",
        "d": "p",
        "n": "u",
        "u": "n",
        "e": "a",
        "a": "e",
    }
)

# Common single-token OCR fixes after cleanup.
OCR_FIXES = {
    "ag0": "ago",
    "0n": "on",
    "t0": "to",
    "g0": "go",
    "n0": "no",
    "s0": "so",
    "d0": "do",
    "0r": "or",
    "0f": "of",
    "l0": "lo",
    "w0rk": "work",
    "sch00l": "school",
    "b00k": "book",
    "g00d": "good",
    "f00d": "food",
    "l00k": "look",
    "t00": "too",
    "z00": "zoo",
}


def _load_lexicon() -> set[str]:
    words: set[str] = set()
    if LEXICON_PATH.exists():
        try:
            with sqlite3.connect(f"file:{LEXICON_PATH.as_posix()}?mode=ro", uri=True) as db:
                for (w,) in db.execute(
                    "SELECT lower(word) FROM entries WHERE length(word) BETWEEN 1 AND 40"
                ):
                    if w:
                        words.add(w)
        except sqlite3.Error:
            pass
    try:
        from wordfreq import top_n_list

        words.update(w.lower() for w in top_n_list("en", 50000))
    except Exception:  # noqa: BLE001
        pass
    # Always keep ultra-short function words.
    words.update({"a", "an", "i", "am", "is", "are", "be", "to", "of", "or", "on", "in", "at"})
    return words


def _fix_upside_down(token: str) -> str:
    return token.translate(_UPSIDE)[::-1]


def _normalize_ocr_token(raw: str) -> str | None:
    t = (raw or "").strip()
    if not t:
        return None
    t = t.replace("¥", "").replace("￥", "").replace("‘", "'").replace("’", "'")
    t = t.replace("（", "(").replace("）", ")").replace("＝", "=")
    t = re.sub(r"\s+", " ", t).strip()
    if LETTER_ONLY.match(t) or PAGE_NUM.match(t):
        return None
    if NOISE_CN.search(t):
        return None
    if t.lower() in {"续表", "附录", "说明"}:
        return None
    # digit/letter confusion
    low = t.lower()
    if low in OCR_FIXES:
        t = OCR_FIXES[low]
        low = t.lower()
    # Fix lone 0 inside alphabetic tokens.
    if re.search(r"[a-zA-Z]", t) and "0" in t:
        t2 = t.replace("0", "o")
        t = t2
        low = t.lower()
    return t


def _primary_lemma(surface: str) -> str:
    m = PRIMARY_FORM.match(surface.strip())
    if not m:
        return surface.strip().lower()
    return m.group(1).replace("'", "'").lower()


def _lemma_in_lexicon(lemma: str, lexicon: set[str]) -> bool:
    if not lexicon:
        return True
    return lemma in lexicon


def _surface_in_lexicon(surface: str, lexicon: set[str]) -> bool:
    if not SURFACE_OK.match(surface):
        return False
    lemma = _primary_lemma(surface)
    if len(lemma) == 1 and lemma in {"a", "i"}:
        return True
    parts = re.split(r"\s*/\s*", re.sub(r"\([^)]*\)", "", surface).strip())
    for part in parts:
        p = _primary_lemma(part)
        if _lemma_in_lexicon(p, lexicon):
            return True
    # Multi-word proper phrases (festivals, place names).
    if " " in surface or surface[:1].isupper():
        return bool(re.match(r"^[A-Za-z][A-Za-z0-9 ''\-/()=]+$", surface))
    return False


def _choose_surface(raw: str, lexicon: set[str]) -> str | None:
    t = _normalize_ocr_token(raw)
    if t is None:
        return None
    if _surface_in_lexicon(t, lexicon):
        return t
    # Upside-down OCR repair on primary token.
    m = PRIMARY_FORM.match(t)
    if m and len(m.group(1)) >= 2:
        flipped = _fix_upside_down(m.group(1).lower())
        rest = t[m.end() :]
        candidate = flipped + rest
        if _surface_in_lexicon(candidate, lexicon):
            return candidate
    # Last resort: well-formed curriculum entry with parentheses / slash, even if rare.
    if ("(" in t or "/" in t) and SURFACE_OK.match(t):
        return t
    return None


def _merge_parenthetical_fragments(tokens: list[str]) -> list[str]:
    """Join EasyOCR/RapidOCR splits like ['be (am', 'is,', 'are)']."""
    out: list[str] = []
    buf = ""
    for tok in tokens:
        if buf:
            buf = f"{buf} {tok}".strip()
            if ")" in tok:
                out.append(buf)
                buf = ""
            continue
        if "(" in tok and ")" not in tok:
            buf = tok
            continue
        out.append(tok)
    if buf:
        out.append(buf)
    return out


_easy_reader = None


def _get_easy_reader():
    global _easy_reader
    if _easy_reader is False:
        return None
    if _easy_reader is not None:
        return _easy_reader
    try:
        import easyocr

        _easy_reader = easyocr.Reader(["en"], gpu=True, verbose=False)
    except Exception:  # noqa: BLE001
        _easy_reader = False
        return None
    return _easy_reader


def _ocr_columns_grouped(ocr: RapidOCR, png_path: Path) -> list[list[str]]:
    """OCR left/right columns separately (needed to stop at 数词表 mid-page)."""
    img = Image.open(png_path).convert("RGB")
    img = ImageEnhance.Contrast(img).enhance(1.6)
    w, h = img.size
    top = int(h * 0.07)
    bot = int(h * 0.96)
    boxes = [
        (int(w * 0.06), top, int(w * 0.50), bot),
        (int(w * 0.50), top, int(w * 0.94), bot),
    ]
    easy = _get_easy_reader()
    columns: list[list[str]] = []
    for box in boxes:
        crop = img.crop(box)
        # Upsample for small type.
        crop = crop.resize((crop.width * 2, crop.height * 2), Image.Resampling.LANCZOS)
        arr = np.array(crop)
        result, _ = ocr(arr)
        col = [line[1] for line in (result or [])]
        # EasyOCR supplemental pass (catches tokens RapidOCR drops, e.g. "bird").
        if easy is not None:
            try:
                extra = easy.readtext(np.array(img.crop(box)), detail=0, paragraph=False)
            except Exception:  # noqa: BLE001
                extra = []
            for tok in extra or []:
                col.append(tok)
        columns.append(_merge_parenthetical_fragments(col))
    return columns


def _ocr_columns(ocr: RapidOCR, png_path: Path) -> list[str]:
    texts: list[str] = []
    for col in _ocr_columns_grouped(ocr, png_path):
        texts.extend(col)
    return texts


def _render_page(doc: pymupdf.Document, page_index: int, out_png: Path, zoom: float = 2.5) -> None:
    page = doc.load_page(page_index)
    pix = page.get_pixmap(matrix=pymupdf.Matrix(zoom, zoom))
    out_png.parent.mkdir(parents=True, exist_ok=True)
    pix.save(str(out_png))


def _collect_from_pages(
    doc: pymupdf.Document,
    ocr: RapidOCR,
    page_indices: range | list[int],
    tmp: Path,
    lexicon: set[str],
    band: str,
    stop_on_markers: bool = False,
) -> list[dict[str, str]]:
    seen: dict[str, str] = {}  # lemma -> surface
    order: list[str] = []
    for idx in page_indices:
        png = tmp / f"ocr_{band}_p{idx + 1:03d}.png"
        _render_page(doc, idx, png)
        # Column-aware: 数词表 often starts mid-left while right column still has Y/Z.
        columns = _ocr_columns_grouped(ocr, png)
        raw_count = sum(len(c) for c in columns)
        page_hit_stop = False
        for col in columns:
            for raw in col:
                if stop_on_markers and any(m in raw for m in STOP_MARKERS):
                    page_hit_stop = True
                    break
                surface = _choose_surface(raw, lexicon)
                if not surface:
                    continue
                lemma = _primary_lemma(surface)
                if not lemma or lemma in seen:
                    continue
                # Drop pure letter headers mistakenly kept.
                if len(lemma) == 1 and lemma not in {"a", "i"}:
                    continue
                if lemma in OCR_JUNK_LEMMAS:
                    continue
                if lemma == "zoo":
                    surface = "zoo"
                seen[lemma] = surface
                order.append(lemma)
            # Continue other columns even after a stop in this column.
        print(
            f"  [{band}] PDF p{idx + 1}: +tokens raw={raw_count} "
            f"unique_total={len(seen)} stopped={page_hit_stop}"
        )
        if page_hit_stop:
            break
    return [{"lemma": lem, "surface": seen[lem], "band": band} for lem in order]


def write_csv(path: Path, rows: list[dict[str, str]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(f, fieldnames=["lemma", "surface", "band"])
        w.writeheader()
        for row in rows:
            w.writerow(row)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--pdf", required=True, type=Path, help="Path to CES2022 PDF")
    ap.add_argument("--out", type=Path, default=DEFAULT_OUT)
    ap.add_argument("--tmp", type=Path, default=DEFAULT_TMP)
    args = ap.parse_args()

    pdf = args.pdf.expanduser().resolve()
    if not pdf.exists():
        print(f"PDF not found: {pdf}", file=sys.stderr)
        return 1

    lexicon = _load_lexicon()
    print(f"Lexicon words loaded: {len(lexicon)}")

    doc = pymupdf.open(str(pdf))
    print(f"PDF pages: {doc.page_count}")
    ocr = RapidOCR()
    args.tmp.mkdir(parents=True, exist_ok=True)

    print("Extracting level2 …")
    level2 = _collect_from_pages(doc, ocr, PDF_LEVEL2_WORDS, args.tmp, lexicon, "level2")
    print("Extracting level3 …")
    level3 = _collect_from_pages(
        doc,
        ocr,
        PDF_LEVEL3_WORDS,
        args.tmp,
        lexicon,
        "level3",
        stop_on_markers=True,
    )
    # Curriculum: 三级 1600 含二级 505 — ensure level3 CSV covers level2 lemmas.
    have = {r["lemma"] for r in level3}
    for row in level2:
        if row["lemma"] not in have:
            level3.append(
                {"lemma": row["lemma"], "surface": row["surface"], "band": "level3"}
            )
            have.add(row["lemma"])

    # Acceptance targets from curriculum notes: 505 / 1600 (±2%).
    l2_n, l3_n = len(level2), len(level3)
    print(f"Counts: level2={l2_n} (target ~505), level3={l3_n} (target ~1600)")

    write_csv(args.out / "level2_words.csv", level2)
    write_csv(args.out / "level3_words.csv", level3)

    manifest = {
        "source": "义务教育英语课程标准（2022年版）附录3 词汇表",
        "source_pdf": str(pdf.name),
        "version": "2022",
        "extract_method": "ocr",
        "ocr_engine": "rapidocr-onnxruntime+easyocr",
        "pdf_page_ranges": {
            "level2_intro_pdf_page": PDF_LEVEL2_INTRO + 1,
            "level2_words_pdf_pages": [PDF_LEVEL2_WORDS.start + 1, PDF_LEVEL2_WORDS.stop],
            "level3_intro_pdf_page": PDF_LEVEL3_INTRO + 1,
            "level3_words_pdf_pages": [PDF_LEVEL3_WORDS.start + 1, PDF_LEVEL3_WORDS.stop],
            "irregular_verbs_pdf_page": PDF_IRREGULAR + 1,
            "note": "Printed page ≈ PDF page − 7 for appendix block",
        },
        "counts": {"level2": l2_n, "level3": l3_n},
        "targets": {"level2": 505, "level3": 1600},
        "extracted_at": datetime.now(timezone.utc).isoformat(),
        "compliance": "word-list strings only; no teaching-case body text stored",
    }
    (args.out / "manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )

    # Diff hints for manual review.
    args.tmp.mkdir(parents=True, exist_ok=True)
    summary = {
        "level2_count": l2_n,
        "level3_count": l3_n,
        "level2_delta_vs_505": l2_n - 505,
        "level3_delta_vs_1600": l3_n - 1600,
        "level2_sample": [r["surface"] for r in level2[:20]],
        "level3_sample": [r["surface"] for r in level3[:20]],
    }
    (args.tmp / "extract_summary.json").write_text(
        json.dumps(summary, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"Wrote {args.out / 'level2_words.csv'}")
    print(f"Wrote {args.out / 'level3_words.csv'}")
    print(f"Wrote {args.out / 'manifest.json'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
