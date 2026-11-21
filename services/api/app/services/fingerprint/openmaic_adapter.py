"""OpenMAIC编排引擎适配器。

OpenMAIC is not vendored in this repo. P0 uses the heuristic splitter;
swap `get_splitter()` when a remote OpenMAIC endpoint is configured.
"""

from __future__ import annotations

from typing import Any, Protocol

from app.services.fingerprint.annotate import annotate_lessons, clean_material_text


class LessonSplitter(Protocol):
    def split(
        self,
        cleaned_text: str,
        *,
        asset_name: str = "",
    ) -> list[dict[str, Any]]:
        ...


class HeuristicSplitter:
    """Chapter/length heuristic — default P0 implementation."""

    def split(
        self,
        cleaned_text: str,
        *,
        asset_name: str = "",
    ) -> list[dict[str, Any]]:
        # Lazy import avoids circular dependency with service.py
        from app.services.fingerprint.service import decompose_text_to_lessons

        return decompose_text_to_lessons(
            cleaned_text,
            asset_name=asset_name,
            annotate=False,
        )


class OpenMaicSplitter:
    """Remote OpenMAIC client stub — raises until endpoint is wired (P1)."""

    def __init__(self, base_url: str | None = None) -> None:
        self.base_url = (base_url or "").rstrip("/")

    def split(
        self,
        cleaned_text: str,
        *,
        asset_name: str = "",
    ) -> list[dict[str, Any]]:
        if not self.base_url:
            raise RuntimeError(
                "OpenMAIC base URL not configured; use HeuristicSplitter for P0"
            )
        raise NotImplementedError(
            "OpenMAIC remote split not implemented in P0 — configure later"
        )


def get_splitter(*, prefer_openmaic: bool = False, openmaic_url: str | None = None) -> LessonSplitter:
    if prefer_openmaic and (openmaic_url or "").strip():
        return OpenMaicSplitter(openmaic_url)
    return HeuristicSplitter()


def decompose_and_annotate(
    raw_or_cleaned: str,
    *,
    asset_name: str = "",
    splitter: LessonSplitter | None = None,
    already_cleaned: bool = False,
) -> tuple[list[dict[str, Any]], str, dict[str, Any]]:
    text = raw_or_cleaned if already_cleaned else clean_material_text(raw_or_cleaned)
    engine = splitter or get_splitter()
    lessons = engine.split(text, asset_name=asset_name)
    return annotate_lessons(lessons)
