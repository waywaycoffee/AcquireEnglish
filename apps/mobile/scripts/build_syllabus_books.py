#!/usr/bin/env python3
"""Deprecated entry — word books now build into the API syllabus tree."""

from __future__ import annotations

import runpy
from pathlib import Path

if __name__ == "__main__":
    target = (
        Path(__file__).resolve().parents[3]
        / "tools"
        / "syllabus"
        / "build_word_books.py"
    )
    runpy.run_path(str(target), run_name="__main__")
