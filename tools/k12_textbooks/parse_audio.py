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

# Beijing-style: 01_Unit One_Lesson 1 Title.mp3
_BEIJING_RE = re.compile(r"^(\d+)_(.+?)_(.+)\.mp3$", re.IGNORECASE)
# PEP / generic: 01_Unit 1 A Let's talk.mp3  or  01_01 Unit 1 A Let's talk.mp3
_PEP_RE = re.compile(
    r"^(\d+)_(?:(\d+)[_\s]+)?(.+)\.mp3$",
    re.IGNORECASE,
)
_LESSON_RE = re.compile(
    r"^Lesson\s+(\d+)\s*(.*)$",
    re.IGNORECASE | re.DOTALL,
)
_UNIT_ONLY_RE = re.compile(r"^Unit\s+([A-Za-z0-9]+)\s*$", re.IGNORECASE)
_UNIT_BODY_RE = re.compile(
    r"^Unit\s+([A-Za-z0-9]+)(?:\s*[_\s]\s*([ABC]))?\s*(.*)$",
    re.IGNORECASE | re.DOTALL,
)
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
    section: str = ""

    def to_dict(self) -> dict:
        return asdict(self)


def _clean(text: str) -> str:
    value = unicodedata.normalize("NFKC", text or "")
    value = value.replace("\u2003", " ").replace("\u3000", " ")
    value = re.sub(r"\s+", " ", value).strip(" ._-\u2014")
    return value


def _unit_token(token: str) -> int | None:
    token = (token or "").lower()
    if token.isdigit():
        return int(token)
    return _WORD_UNITS.get(token)


def _audio_key(seq: int, unit: int | None, section: str, lesson: int | None) -> str:
    if unit is not None and lesson is not None:
        return f"u{unit:02d}_l{lesson:02d}_{seq:02d}"
    if unit is not None and section:
        return f"u{unit:02d}_{section.lower()}_{seq:02d}"
    if unit is not None:
        return f"u{unit:02d}_{seq:02d}"
    return f"{seq:02d}"


def _from_beijing(seq: int, mid: str, rest: str, raw: str) -> TextbookAudioTrack:
    unit = _unit_token(
        (_UNIT_ONLY_RE.match(mid).group(1) if _UNIT_ONLY_RE.match(mid) else "")
    )
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
            audio_key=_audio_key(seq, unit, "", lesson),
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
            audio_key=_audio_key(seq, unit, "letters", None),
        )

    kind = "other"
    lowered = f"{mid} {rest}".lower()
    if "word list" in lowered:
        kind = "wordlist"
    elif "reading for pleasure" in lowered:
        kind = "reading"
    return TextbookAudioTrack(
        seq=seq,
        unit=unit,
        unit_label=unit_label,
        lesson=None,
        kind=kind,
        title=rest or mid,
        source_name=raw,
        audio_key=_audio_key(seq, unit, "", None),
    )


def _from_pep(seq: int, body: str, raw: str) -> TextbookAudioTrack:
    body = _clean(body)
    match = _UNIT_BODY_RE.match(body)
    if not match:
        return TextbookAudioTrack(
            seq=seq,
            unit=None,
            unit_label="",
            lesson=None,
            kind="other",
            title=body,
            source_name=raw,
            audio_key=_audio_key(seq, None, "", None),
        )
    unit = _unit_token(match.group(1))
    section = (match.group(2) or "").upper()
    rest = _clean(match.group(3) or "")
    unit_label = f"Unit {match.group(1)}" + (f" {section}" if section else "")

    kind = "other"
    lowered = rest.lower()
    if "let's spell" in lowered or "lets spell" in lowered:
        kind = "spell"
    elif "let's talk" in lowered or "lets talk" in lowered:
        kind = "talk"
    elif "project" in lowered:
        kind = "project"
    elif "revision" in lowered:
        kind = "revision"
    elif "word" in lowered and "unit" in lowered:
        kind = "wordlist"
    elif "chant" in lowered or "sing" in lowered:
        kind = "song"
    elif rest:
        kind = "activity"

    title = rest or unit_label
    return TextbookAudioTrack(
        seq=seq,
        unit=unit,
        unit_label=unit_label,
        lesson=None,
        kind=kind,
        title=title,
        source_name=raw,
        section=section,
        audio_key=_audio_key(seq, unit, section or kind, None),
    )


def parse_audio_filename(name: str) -> TextbookAudioTrack | None:
    raw = Path(name).name
    if not raw.lower().endswith(".mp3"):
        return None

    # Two-underscore form: Beijing (Unit One_Lesson …) or mid tags like word List.
    beijing = _BEIJING_RE.match(raw)
    if beijing:
        mid = _clean(beijing.group(2))
        rest = _clean(beijing.group(3))
        mid_l = mid.lower()
        if re.match(r"^Unit\s+\d+$", mid, re.I) and re.match(
            r"^[ABC](\s|_)", rest, re.I
        ):
            return _from_pep(int(beijing.group(1)), f"{mid}_{rest}", raw)
        if (
            _UNIT_ONLY_RE.match(mid)
            or re.match(r"^Unit\s+[A-Za-z]+$", mid, re.I)
            or "word list" in mid_l
            or "reading for pleasure" in mid_l
            or mid_l.startswith("lesson")
        ):
            return _from_beijing(int(beijing.group(1)), mid, rest, raw)

    pep = _PEP_RE.match(raw)
    if not pep:
        return None
    return _from_pep(int(pep.group(1)), _clean(pep.group(3)), raw)


def scan_audio_names(names: list[str]) -> list[TextbookAudioTrack]:
    """Parse MP3 basenames (local or netdisk listing) into ordered tracks."""
    tracks: list[TextbookAudioTrack] = []
    for name in sorted(names, key=lambda item: item.lower()):
        if Path(name).suffix.lower() != ".mp3":
            continue
        parsed = parse_audio_filename(Path(name).name)
        if parsed is None:
            raise ValueError(f"无法解析音频文件名：{name}")
        tracks.append(parsed)
    tracks.sort(key=lambda item: item.seq)
    return tracks


def scan_audio_folder(folder: Path) -> list[TextbookAudioTrack]:
    return scan_audio_names([path.name for path in folder.glob("*.mp3")])


def find_pdf(folder: Path) -> Path:
    pdfs = sorted(folder.glob("*.pdf"))
    if not pdfs:
        raise FileNotFoundError(f"目录中没有 PDF：{folder}")
    if len(pdfs) > 1:
        raise ValueError(f"目录中有多个 PDF，请只保留一本：{folder}")
    return pdfs[0]
