"""Import bridge to repo-root shared/aikua_english_prompts.py."""

from __future__ import annotations

import sys
from pathlib import Path

_ROOT = Path(__file__).resolve().parents[3]
_SHARED = _ROOT / 'shared'
if str(_SHARED) not in sys.path:
    sys.path.insert(0, str(_SHARED))

from aikua_english_prompts import (  # noqa: E402
    filter_stream_chunk,
    video_script_system_prompt,
)

__all__ = ['filter_stream_chunk', 'video_script_system_prompt']
