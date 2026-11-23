"""Select evidence from the article excerpt supplied by the reading session."""

import re

_TERMS = re.compile(r"[a-z0-9]+|[\u3400-\u9fff]", re.IGNORECASE)
_STOP = frozenset("a an and are can do does how i in is it me of on or the to what which why you".split())


def _terms(text: str) -> set[str]:
    return set(_TERMS.findall(text.lower())) - _STOP


def select_passages(excerpt: str, question: str) -> list[tuple[int, str]]:
    """Return up to three matching passages with stable excerpt-local numbers."""
    query = _terms(question)
    if not query:
        return []
    passages = [
        sentence.strip()
        for sentence in re.split(r"(?<=[.!?])\s+|(?<=[。！？])|\n+", excerpt[:12000])
        if sentence.strip()
    ]
    ranked = sorted(
        ((len(query & _terms(text)), index, text)
         for index, text in enumerate(passages, start=1)),
        key=lambda item: (-item[0], item[1]),
    )
    return [(index, text[:600]) for score, index, text in ranked[:3] if score]
