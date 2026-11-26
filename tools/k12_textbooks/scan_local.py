"""Scan a local 教材 tree for English volumes (PDF + MP3) ready to import."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
from dataclasses import asdict, dataclass
from pathlib import Path

from parse_audio import parse_audio_filename

ROOT_DEFAULT = Path(__file__).resolve().parents[2] / "docs" / "教材"

# Higher score = more popular / preferred for first-wave ECS seeding.
HOT_EDITIONS: list[tuple[re.Pattern[str], str, str, str, int]] = [
    # edition_key, edition_label, publisher, score
    (re.compile(r"人教.*PEP|PEP.*人教|人教版（PEP）"), "pep-y3", "人教版 PEP", "人民教育出版社", 100),
    (re.compile(r"人教版（一年级起点）|人教.*一年级起点"), "pep-y1", "人教版（一年级起点）", "人民教育出版社", 95),
    (re.compile(r"Go\s*for\s*it|人教.*初中|人教版\s*Go", re.I), "pep-go", "人教版 Go for it!", "人民教育出版社", 95),
    (re.compile(r"外研"), "fltrp-y3", "外研社版", "外语教学与研究出版社", 90),
    (re.compile(r"译林"), "yilin-y3", "译林版", "译林出版社", 85),
    (re.compile(r"北京版|北京出版社"), "beijing", "北京版", "北京出版社", 88),
    (re.compile(r"北师"), "bnup", "北师大版", "北京师范大学出版社", 70),
    (re.compile(r"冀教"), "hebei", "冀教版", "河北教育出版社", 55),
]

_GRADE_MAP = {
    "一年级": ("k12_g1", "primary", "A1"),
    "二年级": ("k12_g2", "primary", "A1"),
    "三年级": ("k12_g3", "primary", "A1"),
    "四年级": ("k12_g4", "primary", "A1"),
    "五年级": ("k12_g5", "primary", "A2"),
    "六年级": ("k12_g6", "primary", "A2"),
    "七年级": ("k12_j1", "junior", "A2"),
    "八年级": ("k12_j2", "junior", "A2"),
    "九年级": ("k12_j3", "junior", "B1"),
    "高一": ("k12_s1", "senior", "B1"),
    "高二": ("k12_s2", "senior", "B1"),
    "高三": ("k12_s3", "senior", "B2"),
}

_VOLUME_MAP = {
    "上册": ("a", "上册"),
    "下册": ("b", "下册"),
    "全一册": ("full", "全一册"),
    "全册": ("full", "全一册"),
}


@dataclass
class LocalTextbookCandidate:
    path: str
    stage_dir: str
    edition_folder: str
    grade_label: str
    volume_label: str
    pdf_count: int
    mp3_count: int
    parseable_mp3: int
    pdf_name: str
    hot: bool
    score: int
    edition_key: str
    edition: str
    publisher: str
    grade_id: str
    stage: str
    level: str
    volume_key: str
    book_id: str
    catalog_id: str
    title: str
    title_zh: str
    ready: bool
    notes: list[str]

    def to_dict(self) -> dict:
        return asdict(self)


_EDITOR_ASCII = {
    "吴欣": "wuxin",
    "刘兆义": "liuzhaoyi",
    "孙有中": "sunyouzhong",
    "陈琳": "chenlin",
    "桂诗春": "guishichun",
    "苗兴伟": "miaoxingwei",
    "郝建平": "haojianping",
    "龚亚夫": "gongyafu",
    "鲁宗干": "luzonggan",
}


def _editor_suffix(folder_name: str) -> str:
    """Disambiguate same brand with different chief editors in the folder name."""
    match = re.search(r"主编[:：]\s*([^）\)]+)", folder_name)
    if not match:
        return ""
    raw = re.sub(r"\s+", "", match.group(1))
    # Prefer first known editor token when folders list two names with &.
    for name, ascii_name in _EDITOR_ASCII.items():
        if name in raw:
            return ascii_name
    compact = re.sub(r"[^\w]+", "", raw)
    if not compact:
        return ""
    # ASCII-safe fallback so ECS paths stay URL-friendly.
    return hashlib.sha1(compact.encode("utf-8")).hexdigest()[:8]


def _match_edition(folder_name: str) -> tuple[str, str, str, int, bool]:
    for pattern, key, label, publisher, score in HOT_EDITIONS:
        if pattern.search(folder_name):
            suffix = _editor_suffix(folder_name)
            # Keep stable ids for single-line brands (北京版); disambiguate 外研/人教分册。
            if suffix and key.startswith(("fltrp", "pep")):
                key = f"{key}-{suffix}"
            return key, label, publisher, score, True
    # Non-hot: keep discoverable but low score.
    slug = re.sub(r"[^\w\u4e00-\u9fff]+", "-", folder_name).strip("-").lower()
    slug = slug[:40] or "other"
    return slug, folder_name, "", 10, False


def _pick_pdf(folder: Path) -> Path | None:
    pdfs = sorted(folder.glob("*.pdf")) + sorted(folder.glob("*.PDF"))
    # Deduplicate case on Windows.
    uniq: dict[str, Path] = {}
    for path in pdfs:
        uniq[path.name.lower()] = path
    pdfs = list(uniq.values())
    if not pdfs:
        return None
    if len(pdfs) == 1:
        return pdfs[0]

    def rank(path: Path) -> tuple[int, int, str]:
        name = path.name
        score = 0
        if "英语" in name or "English" in name:
            score += 20
        if "义务教育教科书" in name:
            score += 10
        if "教师" in name or "教案" in name or "答案" in name:
            score -= 50
        return (score, path.stat().st_size, name)

    return sorted(pdfs, key=rank, reverse=True)[0]


def _volume_from_parts(parts: list[str]) -> tuple[str, str] | None:
    for part in reversed(parts):
        if part in _VOLUME_MAP:
            return _VOLUME_MAP[part]
    return None


def _grade_from_parts(parts: list[str]) -> tuple[str, str, str, str] | None:
    for part in parts:
        if part in _GRADE_MAP:
            grade_id, stage, level = _GRADE_MAP[part]
            return part, grade_id, stage, level
    return None


def scan_local_tree(
    root: Path,
    *,
    english_only: bool = True,
    hot_only: bool = False,
    min_mp3: int = 5,
) -> list[LocalTextbookCandidate]:
    root = root.resolve()
    if not root.is_dir():
        raise FileNotFoundError(f"教材根目录不存在：{root}")

    out: list[LocalTextbookCandidate] = []
    for folder in sorted({p.parent for p in root.rglob("*.mp3") if p.is_file()}):
        rel = folder.relative_to(root)
        parts = list(rel.parts)
        if english_only and "英语" not in parts:
            continue
        pdf = _pick_pdf(folder)
        mp3s = sorted({p.name.lower(): p for p in folder.glob("*.mp3")}.values())
        if pdf is None or len(mp3s) < min_mp3:
            continue

        stage_dir = parts[0] if parts else ""
        # Prefer …/英语/{edition}/{grade}/{volume}
        edition_folder = ""
        if "英语" in parts:
            idx = parts.index("英语")
            edition_folder = parts[idx + 1] if idx + 1 < len(parts) else folder.name
        else:
            edition_folder = folder.name

        edition_key, edition, publisher, score, hot = _match_edition(edition_folder)
        if hot_only and not hot:
            continue

        grade_info = _grade_from_parts(parts)
        volume_info = _volume_from_parts(parts)
        notes: list[str] = []
        parseable = sum(1 for p in mp3s if parse_audio_filename(p.name))
        if parseable < len(mp3s):
            notes.append(f"有 {len(mp3s) - parseable} 个 MP3 文件名未能按课次解析")

        ready = True
        if grade_info is None:
            ready = False
            notes.append("路径中未识别年级")
            grade_label, grade_id, stage, level = "", "", "primary", "A1"
        else:
            grade_label, grade_id, stage, level = grade_info
        if volume_info is None:
            ready = False
            notes.append("路径中未识别上/下册")
            volume_key, volume_label = "", ""
        else:
            volume_key, volume_label = volume_info

        if stage_dir in ("小学", "初中", "高中"):
            expected = {"小学": "primary", "初中": "junior", "高中": "senior"}[stage_dir]
            if grade_info and stage != expected:
                notes.append(f"路径学段 {stage_dir} 与年级 {grade_label} 不一致")

        grade_short = grade_id.replace("k12_", "") if grade_id else "x"
        book_id = f"{edition_key}-{grade_short}-{volume_key}" if volume_key else ""
        catalog_id = (
            f"k12-textbook:{edition_key}:{grade_id}:{volume_key}"
            if grade_id and volume_key
            else ""
        )
        title_zh = f"英语 {grade_label} {volume_label}".strip()
        title = f"English · {grade_label} {volume_label}".strip()
        if not book_id:
            ready = False

        # Multiple PDFs: note which one we pick.
        pdf_names = sorted({p.name for p in folder.glob("*.pdf")})
        if len(pdf_names) > 1:
            notes.append(f"目录有 {len(pdf_names)} 个 PDF，将使用：{pdf.name}")

        out.append(
            LocalTextbookCandidate(
                path=str(folder),
                stage_dir=stage_dir,
                edition_folder=edition_folder,
                grade_label=grade_label,
                volume_label=volume_label,
                pdf_count=len(pdf_names),
                mp3_count=len(mp3s),
                parseable_mp3=parseable,
                pdf_name=pdf.name,
                hot=hot,
                score=score + min(20, parseable // 5),
                edition_key=edition_key,
                edition=edition,
                publisher=publisher,
                grade_id=grade_id,
                stage=stage,
                level=level,
                volume_key=volume_key,
                book_id=book_id,
                catalog_id=catalog_id,
                title=title,
                title_zh=title_zh,
                ready=ready and parseable >= min_mp3,
                notes=notes,
            )
        )

    out.sort(key=lambda c: (-c.score, c.edition_folder, c.grade_id, c.volume_key))
    return out


def import_command(candidate: LocalTextbookCandidate) -> str:
    return (
        "python tools/k12_textbooks/import_book.py "
        f"--source \"{candidate.path}\" "
        f"--book-id {candidate.book_id} "
        f"--catalog-id \"{candidate.catalog_id}\" "
        f"--title \"{candidate.title}\" "
        f"--title-zh \"{candidate.title_zh}\" "
        f"--edition \"{candidate.edition}\" "
        f"--publisher \"{candidate.publisher or candidate.edition}\" "
        f"--grade-id {candidate.grade_id} "
        f"--stage {candidate.stage} "
        f"--volume \"{candidate.volume_label}\" "
        f"--level {candidate.level}"
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=ROOT_DEFAULT)
    parser.add_argument("--hot-only", action="store_true", help="只列热门版本")
    parser.add_argument("--ready-only", action="store_true", help="只列可直接导入的")
    parser.add_argument("--min-mp3", type=int, default=5)
    parser.add_argument("--json", type=Path, default=None, help="写出候选 JSON")
    parser.add_argument(
        "--print-import",
        action="store_true",
        help="打印 hot+ready 的 import_book 命令",
    )
    args = parser.parse_args()

    rows = scan_local_tree(
        args.root, hot_only=args.hot_only, min_mp3=args.min_mp3
    )
    if args.ready_only:
        rows = [r for r in rows if r.ready]

    summary = {
        "root": str(args.root.resolve()),
        "count": len(rows),
        "hot": sum(1 for r in rows if r.hot),
        "ready": sum(1 for r in rows if r.ready),
        "books": [r.to_dict() for r in rows],
    }
    if args.json:
        args.json.parent.mkdir(parents=True, exist_ok=True)
        args.json.write_text(
            json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8"
        )
        print(f"wrote {args.json} ({summary['count']} books)", flush=True)

    print(
        f"本地英语教材候选：{summary['count']} 册 "
        f"（热门 {summary['hot']} · 可导入 {summary['ready']}）",
        flush=True,
    )
    for row in rows:
        flag = "HOT" if row.hot else "   "
        ready = "OK" if row.ready else ".."
        print(
            f"[{flag}|{ready}] score={row.score:3d}  "
            f"{row.edition_folder} / {row.grade_label}{row.volume_label}  "
            f"mp3={row.mp3_count}  {row.book_id or '-'}",
            flush=True,
        )
        for note in row.notes:
            print(f"         - {note}", flush=True)

    if args.print_import:
        print("\n# import commands (hot + ready)", flush=True)
        for row in rows:
            if row.hot and row.ready:
                print(import_command(row), flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
