"""Load thin first-party exam practice packs (text-only; audio via ECS URLs)."""

from __future__ import annotations

import json
from functools import lru_cache
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[2] / "data" / "exam_packs"

# Fallback map: family_id → pack file stem when dedicated pack missing.
_TRACK_DEFAULT = {
    "k12": "pack_k12_general",
    "cambridge": "pack_ket",
    "cet": "pack_cet4",
    "postgraduate": "pack_kaoyan",
    "toefl": "pack_toefl",
    "ielts": "pack_ielts_ac",
}

_FAMILY_TRACK = {
    "k12_g1": "k12",
    "k12_g2": "k12",
    "k12_g3": "k12",
    "k12_g4": "k12",
    "k12_g5": "k12",
    "k12_g6": "k12",
    "k12_j1": "k12",
    "k12_j2": "k12",
    "k12_j3": "k12",
    "zhongkao": "k12",
    "k12_s1": "k12",
    "k12_s2": "k12",
    "k12_s3": "k12",
    "gaokao": "k12",
    "cn_english_taxonomy": "k12",
    "race_middle": "k12",
    "race_high": "k12",
    "cloth_cloze": "k12",
    "scques_grammar": "k12",
    "ket": "cambridge",
    "pet": "cambridge",
    "cet4": "cet",
    "cet6": "cet",
    "kaoyan": "postgraduate",
    "toefl": "toefl",
    "ielts_ac": "ielts",
    "ielts_gt": "ielts",
}


def _packs_dir() -> Path:
    ROOT.mkdir(parents=True, exist_ok=True)
    return ROOT


@lru_cache(maxsize=64)
def _read_pack_file(stem: str) -> dict[str, Any] | None:
    path = _packs_dir() / f"{stem}.json"
    if not path.is_file():
        return None
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None
    return data if isinstance(data, dict) else None


def resolve_pack_stem(family_id: str) -> str:
    fam = (family_id or "").strip()
    direct = f"pack_{fam}"
    if (_packs_dir() / f"{direct}.json").is_file():
        return direct
    # aliases
    aliases = {
        "ielts_gt": "pack_ielts_ac",
        "cet6": "pack_cet6",
        "gaokao": "pack_gaokao",
        "zhongkao": "pack_zhongkao",
        "pet": "pack_ket",
        "race": "pack_race_middle",
        "cloth": "pack_cloth_cloze",
        "scques": "pack_scques_grammar",
        "cn_english": "pack_cn_english_taxonomy",
    }
    if fam in aliases and (_packs_dir() / f"{aliases[fam]}.json").is_file():
        return aliases[fam]
    track = _FAMILY_TRACK.get(fam, "cet")
    return _TRACK_DEFAULT.get(track, "pack_cet4")


def list_catalog() -> list[dict[str, Any]]:
    items: list[dict[str, Any]] = []
    for path in sorted(_packs_dir().glob("pack_*.json")):
        data = _read_pack_file(path.stem) or {}
        sections = data.get("sections") or {}
        counts: dict[str, int] = {}
        if isinstance(sections, dict):
            for skill, raw in sections.items():
                counts[str(skill)] = len(raw) if isinstance(raw, list) else 0
        if isinstance(data.get("counts"), dict):
            counts = {str(k): int(v) for k, v in data["counts"].items()}
        items.append(
            {
                "id": path.stem,
                "family_id": data.get("family_id") or path.stem.replace("pack_", "", 1),
                "title": data.get("title") or path.stem,
                "cefr": data.get("cefr") or "",
                "skills": list(counts.keys()) or list(sections.keys()),
                "counts": counts,
                "version": data.get("version"),
            }
        )
    return items


def get_pack(family_id: str) -> dict[str, Any]:
    stem = resolve_pack_stem(family_id)
    data = _read_pack_file(stem)
    if data is None:
        # Ultimate fallback: empty but valid shell
        return {
            "family_id": family_id,
            "title": family_id,
            "cefr": "B1",
            "version": 1,
            "sections": {},
            "mock": {"duration_minutes": 45, "sections": ["vocab"]},
            "resolved_from": stem,
            "missing": True,
        }
    out = dict(data)
    out["resolved_from"] = stem
    out["requested_family_id"] = family_id
    out["missing"] = False
    return out


def section_items(family_id: str, skill: str, *, limit: int = 200) -> list[dict[str, Any]]:
    pack = get_pack(family_id)
    sections = pack.get("sections") or {}
    raw = sections.get(skill) or []
    if not isinstance(raw, list):
        return []
    return [x for x in raw if isinstance(x, dict)][:limit]
