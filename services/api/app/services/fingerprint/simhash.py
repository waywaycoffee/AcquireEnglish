"""64-bit SimHash + 4×16-bit banding for fingerprint recall."""

from __future__ import annotations

import hashlib
import re
from collections.abc import Iterable

_TOKEN_RE = re.compile(r"[A-Za-z0-9\u4e00-\u9fff]+")

DEFAULT_BLOCK_CHARS = 512


def tokenize(text: str) -> list[str]:
    return [t.lower() for t in _TOKEN_RE.findall(text or "") if t]


def split_blocks(text: str, size: int = DEFAULT_BLOCK_CHARS) -> list[str]:
    cleaned = re.sub(r"\s+", " ", (text or "").strip())
    if not cleaned:
        return []
    size = max(64, int(size))
    blocks = [cleaned[i : i + size] for i in range(0, len(cleaned), size)]
    # Drop a tiny trailing stub that would dilute matching.
    if len(blocks) > 1 and len(blocks[-1]) < size // 4:
        blocks[-2] = blocks[-2] + blocks[-1]
        blocks.pop()
    return blocks


def _feature_hash(token: str) -> int:
    digest = hashlib.md5(token.encode("utf-8")).digest()
    return int.from_bytes(digest[:8], "big")


def simhash64(text: str) -> int:
    tokens = tokenize(text)
    if not tokens:
        return 0
    weights = [0] * 64
    for tok in tokens:
        h = _feature_hash(tok)
        for bit in range(64):
            if (h >> bit) & 1:
                weights[bit] += 1
            else:
                weights[bit] -= 1
    out = 0
    for bit, w in enumerate(weights):
        if w >= 0:
            out |= 1 << bit
    return out


def to_bands(h: int) -> list[int]:
    """Split 64-bit hash into 4×16-bit band values."""
    return [(int(h) >> (16 * i)) & 0xFFFF for i in range(4)]


def hamming(a: int, b: int) -> int:
    return (int(a) ^ int(b)).bit_count()


def similarity_from_hamming(dist: int) -> float:
    return 1.0 - (max(0, int(dist)) / 64.0)


def count_similar_blocks(
    blocks_a: Iterable[int],
    blocks_b: Iterable[int],
    max_dist: int,
) -> int:
    """Count blocks in A whose nearest neighbor in B is within max_dist."""
    b_list = [int(x) for x in blocks_b]
    if not b_list:
        return 0
    similar = 0
    for ha in blocks_a:
        nearest_dist = min(hamming(int(ha), hb) for hb in b_list)
        if nearest_dist <= max_dist:
            similar += 1
    return similar


def compute_simhash_blocks(
    text: str, *, block_chars: int = DEFAULT_BLOCK_CHARS, max_blocks: int = 64
) -> list[int]:
    blocks = split_blocks(text, size=block_chars)
    if max_blocks > 0 and len(blocks) > max_blocks:
        # Keep evenly spaced blocks so long books stay comparable.
        step = len(blocks) / max_blocks
        blocks = [blocks[int(i * step)] for i in range(max_blocks)]
    return [simhash64(b) for b in blocks]


def parse_simhash_blocks(raw: list | str | None) -> list[int]:
    if raw is None:
        return []
    if isinstance(raw, str):
        import json

        try:
            raw = json.loads(raw)
        except json.JSONDecodeError:
            return []
    out: list[int] = []
    for item in raw or []:
        if isinstance(item, int):
            out.append(item)
        elif isinstance(item, str):
            try:
                out.append(int(item, 0))
            except ValueError:
                continue
    return out


def serialize_simhash_blocks(blocks: list[int]) -> list[str]:
    return [str(int(h)) for h in blocks]
