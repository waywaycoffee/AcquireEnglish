"""Import bridge to repo-root shared/aikua_english_prompts.py."""

from __future__ import annotations

import sys
from pathlib import Path

_ROOT = Path(__file__).resolve().parents[3]
_SHARED = _ROOT / 'shared'
if str(_SHARED) not in sys.path:
    sys.path.insert(0, str(_SHARED))

from aikua_english_prompts import (  # noqa: E402
    compose_system_prompt,
    error_recover_system_prompt,
    filter_stream_chunk,
    interrupt_system_prompt,
    level_switch_system_prompt,
    realtime_system_prompt,
    session_anchor_prompt,
    silence_system_prompt,
    ui_copy,
)

__all__ = [
    'compose_system_prompt',
    'error_recover_system_prompt',
    'filter_stream_chunk',
    'interrupt_system_prompt',
    'level_switch_system_prompt',
    'realtime_system_prompt',
    'session_anchor_prompt',
    'silence_system_prompt',
    'ui_copy',
]
