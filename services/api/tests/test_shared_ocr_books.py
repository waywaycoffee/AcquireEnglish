from __future__ import annotations

import pytest

from app.shared_ocr_book_store import evaluate_ocr_pack, normalize_content_sha


def test_normalize_and_quality() -> None:
    assert normalize_content_sha("A" * 64) == "a" * 64
    with pytest.raises(ValueError):
        normalize_content_sha("short")
    ok, score, reason = evaluate_ocr_pack(
        plain_text=" ".join(["word"] * 40),
        page_count=2,
    )
    assert ok is True
    assert score >= 0.45
    assert reason == "ok"
    bad, _, why = evaluate_ocr_pack(plain_text="too short", page_count=1)
    assert bad is False
    assert "short" in why or "few" in why
