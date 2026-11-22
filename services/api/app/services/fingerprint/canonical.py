"""Format-independent fingerprint input for extracted English text."""

from __future__ import annotations

import re
import unicodedata

from .simhash import tokenize

TEXT_SOURCE_TYPES = frozenset({"pdf_text", "epub", "srt", "video_subtitle"})
CANONICAL_SOURCE_TYPE = "content_text"

_CUE_LINE = re.compile(r"^\s*(?:\d{1,6}\s+)?(?:\d{1,2}:)?\d{1,2}:\d{2}[,.]\d{1,3}\s*-->.*$", re.MULTILINE)
_TIMECODE = re.compile(r"\b(?:\d{1,2}:)?\d{1,2}:\d{2}[,.]\d{1,3}\b")


def fingerprint_input(text: str, source_type: str) -> str:
    """Ignore PDF line wrapping, EPUB markup spacing and subtitle cue timing."""
    if source_type not in TEXT_SOURCE_TYPES:
        return (text or "").strip()
    value = unicodedata.normalize("NFKC", text or "")
    value = _CUE_LINE.sub(" ", value)
    value = _TIMECODE.sub(" ", value)
    value = re.sub(r"(?m)^\s*\d{1,6}\s*$", " ", value)
    return " ".join(tokenize(value))


def compatible_source_types(source_type: str) -> set[str]:
    if source_type in TEXT_SOURCE_TYPES:
        # Include legacy source-specific fingerprints until they are reindexed.
        return set(TEXT_SOURCE_TYPES) | {CANONICAL_SOURCE_TYPE}
    return {source_type}
