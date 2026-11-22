"""Resolve DeepSeek / OpenAI-compatible credentials from process env + sidecar .env files."""

from __future__ import annotations

import os
from pathlib import Path


_ENV_CANDIDATES = (
    Path("/opt/acquireenglish/services/api/.env"),
    Path("/opt/acquireenglish/tools/oral_coach/.env"),
    Path("/opt/acquireenglish/tools/digital_human_coach/.env"),
    Path(__file__).resolve().parents[2] / ".env",
    Path(__file__).resolve().parents[3] / "tools" / "oral_coach" / ".env",
    Path(__file__).resolve().parents[3] / "tools" / "digital_human_coach" / ".env",
)


def _parse_dotenv(path: Path) -> dict[str, str]:
    out: dict[str, str] = {}
    if not path.is_file():
        return out
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return out
    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, val = line.partition("=")
        key = key.strip()
        val = val.strip().strip("'").strip('"')
        if key and val:
            out[key] = val
    return out


def _lookup(*names: str) -> str:
    for name in names:
        v = (os.getenv(name, "") or "").strip()
        if v:
            return v
    for path in _ENV_CANDIDATES:
        data = _parse_dotenv(path)
        for name in names:
            v = (data.get(name) or "").strip()
            if v:
                return v
    return ""


def resolve_deepseek() -> dict[str, str]:
    """Return key/base/model for DeepSeek chat completions (OpenAI-compatible)."""
    key = _lookup("DEEPSEEK_API_KEY", "OPENAI_API_KEY")
    base = (
        _lookup("OPENAI_BASE_URL", "DEEPSEEK_BASE_URL")
        or "https://api.deepseek.com/v1"
    ).rstrip("/")
    model = _lookup("DEEPSEEK_MODEL", "OPENAI_MODEL") or "deepseek-chat"
    return {"key": key, "base": base, "model": model}
