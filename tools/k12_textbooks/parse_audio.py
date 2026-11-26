"""Parse K12 textbook companion MP3 filenames into unit/lesson rows."""

from __future__ import annotations

import re
import unicodedata
from dataclasses import asdict, dataclass
from pathlib import Path

_WORD_UNITS = {
    "one": 1,
    "two": 2,
    "three": 3,
    "four": 4,
    "five": 5,
    "six": 6,
    "seven": 7,
    "eight": 8,
    "nine": 9,
    "ten": 10,
    "eleven": 11,
    "twelve": 12,
}

_FILE_RE = re.compile(r"^(\d+)_(.+?)_(.+)\.mp3$", re.IGNORECASE)
_LESSON_RE = re.compile(
    r"^Lesson\s+(\d+)\s*(.*)$",
    re.IGNORECASE | re.DOTALL,
)
_UNIT_RE = re.compile(r"^Unit\s+([A-Za-z0-9]+)\s*$", re.IGNORECASE)
_LETTERS_RE = re.compile(
    r"^Letters\s+and\s+Sounds\s*(.*)$",
    re.IGNORECASE | re.DOTALL,
)


@dataclass(frozen=True)
class TextbookAudioTrack:
    seq: int
    unit: int | None
    unit_label: str
    lesson: int | None
    kind: str
    title: str
    source_name: str
    audio_key: str

    def to_dict(self) -> dict:
        return asdict(self)


def _clean(text: str) -> str:
    value = unicodedata.normalize("NFKC", text or "")
    value = value.replace("\u2003", " ").replace("\u3000", " ")
    value = re.sub(r"\s+", " ", value).strip(" ._-\u2014")
    return value


def _unit_number(label: str) -> int | None:
    cleaned = _clean(label)
    match = _UNIT_RE.match(cleaned)
    if not match:
        return None
    token = match.group(1).lower()
    if token.isdigit():
        return int(token)
    return _WORD_UNITS.get(token)


def parse_audio_filename(name: str) -> TextbookAudioTrack | None:
    raw = Path(name).name
    match = _FILE_RE.match(raw)
    if not match:
        return None
    seq = int(match.group(1))
    mid = _clean(match.group(2))
    rest = _clean(match.group(3))
    unit = _unit_number(mid)
    unit_label = mid

    lesson_match = _LESSON_RE.match(rest)
    if lesson_match:
        lesson = int(lesson_match.group(1))
        title = _clean(lesson_match.group(2)) or f"Lesson {lesson}"
        kind = "revision" if title.lower().startswith("revision") else "lesson"
        return TextbookAudioTrack(
            seq=seq,
            unit=unit,
            unit_label=unit_label,
            lesson=lesson,
            kind=kind,
            title=title,
            source_name=raw,
            audio_key=f"{seq:02d}",
        )

    letters_match = _LETTERS_RE.match(rest)
    if letters_match or rest.lower().startswith("letters and sounds"):
        title = _clean(letters_match.group(1) if letters_match else rest)
        if title.lower().startswith("letters and sounds"):
            title = _clean(title[len("letters and sounds") :])
        return TextbookAudioTrack(
            seq=seq,
            unit=unit,
            unit_label=unit_label,
            lesson=None,
            kind="letters",
            title=title or "Letters and Sounds",
            source_name=raw,
            audio_key=f"{seq:02d}",
        )

    kind = "other"
    lowered = f"{mid} {rest}".lower()
    if "word list" in lowered:
        kind = "wordlist"
    elif "reading for pleasure" in lowered:
        kind = "reading"
    title = rest or mid
    return TextbookAudioTrack(
        seq=seq,
        unit=unit,
        unit_label=unit_label,
        lesson=None,
        kind=kind,
        title=title,
        source_name=raw,
        audio_key=f"{seq:02d}",
    )


def scan_audio_folder(folder: Path) -> list[TextbookAudioTrack]:
    tracks: list[TextbookAudioTrack] = []
    for path in sorted(folder.glob("*.mp3")):
        parsed = parse_audio_filename(path.name)
        if parsed is None:
            raise ValueError(f"无法解析音频文件名：{path.name}")
        tracks.append(parsed)
    tracks.sort(key=lambda item: item.seq)
    return tracks


def find_pdf(folder: Path) -> Path:
    pdfs = sorted(folder.glob("*.pdf"))
    if not pdfs:
        raise FileNotFoundError(f"目录中没有 PDF：{folder}")
    if len(pdfs) > 1:
        raise ValueError(f"目录中有多个 PDF，请只保留一本：{folder}")
    return pdfs[0]
