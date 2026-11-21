"""JSON pre-generation caches under media_cache_dir/misc/pregen/."""

from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path
from typing import Any

from app.services import content_media as cm

_SAFE = re.compile(r"[^a-zA-Z0-9_\-\.]+")


def _root() -> Path:
    root = cm.namespace_root("misc") / "pregen"
    root.mkdir(parents=True, exist_ok=True)
    return root


def _safe_name(raw: str, *, fallback: str = "item") -> str:
    text = _SAFE.sub("-", (raw or "").strip().lower()).strip("-.")
    return text or fallback


def sentence_key(sentence: str, *, source_lang: str = "en", target_lang: str = "zh") -> str:
    payload = f"{source_lang}|{target_lang}|{' '.join(sentence.strip().split())}"
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()[:40]


def _read_json(path: Path) -> dict[str, Any] | None:
    if not path.is_file():
        return None
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except Exception:  # noqa: BLE001
        return None
    return data if isinstance(data, dict) else None


def _write_json(path: Path, payload: dict[str, Any]) -> dict[str, Any]:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    return payload


def get_sentence_translation(
    sentence: str,
    *,
    source_lang: str = "en",
    target_lang: str = "zh",
) -> dict[str, Any] | None:
    key = sentence_key(sentence, source_lang=source_lang, target_lang=target_lang)
    return _read_json(_root() / "sentences" / f"{key}.json")


def put_sentence_translation(
    *,
    sentence: str,
    translation: str,
    source_lang: str = "en",
    target_lang: str = "zh",
) -> dict[str, Any]:
    key = sentence_key(sentence, source_lang=source_lang, target_lang=target_lang)
    payload = {
        "key": key,
        "sentence": " ".join(sentence.strip().split()),
        "translation": translation.strip(),
        "source_lang": source_lang,
        "target_lang": target_lang,
    }
    return _write_json(_root() / "sentences" / f"{key}.json", payload)


def get_vocab_enrich(word: str) -> dict[str, Any] | None:
    name = _safe_name(word, fallback="word")
    return _read_json(_root() / "vocab" / f"{name}.json")


def put_vocab_enrich(word: str, payload: dict[str, Any]) -> dict[str, Any]:
    name = _safe_name(word, fallback="word")
    body = dict(payload)
    body["word"] = word.strip().lower()
    return _write_json(_root() / "vocab" / f"{name}.json", body)


def get_oral_topics(key: str) -> dict[str, Any] | None:
    name = _safe_name(key, fallback="topics")
    return _read_json(_root() / "oral_topics" / f"{name}.json")


def put_oral_topics(key: str, topics: list[str], *, meta: dict[str, Any] | None = None) -> dict[str, Any]:
    name = _safe_name(key, fallback="topics")
    cleaned = [str(t).strip() for t in topics if str(t).strip()]
    payload: dict[str, Any] = {"key": name, "topics": cleaned}
    if meta:
        payload["meta"] = meta
    return _write_json(_root() / "oral_topics" / f"{name}.json", payload)
