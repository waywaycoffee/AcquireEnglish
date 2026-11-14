#!/usr/bin/env python3
"""Fill missing English and/or Chinese subtitles for one episode video.

Uses vendored projects:
  - mateusz-kow/auto-subs → local Whisper transcription → SRT (missing EN)
  - giakinh0823/whisper-subtitle-generator utils → SRT writing / audio extract helpers

Chinese fill when only ZH is missing uses a lightweight EN→ZH path via Whisper
segments when --need-chinese and English SRT already exists: we keep EN cues and
emit a ZH sidecar by machine-translating with openai-whisper's sibling offline
path is NOT used (Whisper task=translate → English only). Instead callers should
prefer App-side EN→ZH; this CLI still can emit EN SRT for the ASR side.

Stdout JSON:
  {"ok": true, "enPath": "...", "zhPath": null, "engine": "auto-subs"}
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path


def _vendor_paths(root: Path) -> None:
    auto_subs_src = root / "vendor" / "auto-subs" / "src"
    wsg = root / "vendor" / "whisper-subtitle-generator"
    if auto_subs_src.is_dir():
        sys.path.insert(0, str(auto_subs_src))
    if wsg.is_dir():
        sys.path.insert(0, str(wsg))


def _fail(message: str, code: int = 2) -> None:
    print(json.dumps({"ok": False, "error": message}, ensure_ascii=False))
    raise SystemExit(code)


def _transcribe_english(
    video: Path,
    out_en: Path,
    model: str,
) -> Path:
    try:
        from autosubs import transcribe  # type: ignore
    except ImportError as exc:
        _fail(
            "auto-subs not importable. Run tools/subtitle/bootstrap.sh "
            f"({exc})"
        )

    out_en.parent.mkdir(parents=True, exist_ok=True)
    # Prefer English-tuned models when caller passes tiny/base/small without .en
    model_name = model.strip() or "base.en"
    srt = transcribe(str(video), "srt", model_name=model_name, max_chars=42)
    out_en.write_text(srt, encoding="utf-8")
    return out_en


def _maybe_translate_via_wsg_style(
    video: Path,
    out_dir: Path,
    model: str,
) -> Path | None:
    """Optional: use whisper-subtitle-generator style pipeline for EN SRT.

    Whisper's task=translate always yields English, so this path is an alternate
    EN engine, not a ZH filler.
    """
    try:
        import whisper  # type: ignore
        from whisper_subtitle_generator.utils import (  # type: ignore
            extract_audio,
            write_srt,
        )
    except ImportError:
        return None

    out_dir.mkdir(parents=True, exist_ok=True)
    audio = out_dir / "_fill_audio.wav"
    if not extract_audio(str(video), str(audio)):
        return None
    try:
        wmodel = whisper.load_model(model.replace(".en", "") or "base")
        result = wmodel.transcribe(
            str(audio),
            task="transcribe",
            language="en",
            verbose=False,
        )
        en_path = out_dir / "en.auto.srt"
        write_srt(result["segments"], str(en_path))
        return en_path
    finally:
        if audio.exists():
            audio.unlink(missing_ok=True)


def main() -> None:
    root = Path(__file__).resolve().parent
    _vendor_paths(root)

    parser = argparse.ArgumentParser(
        description="Fill missing EN/ZH subtitles (auto-subs + whisper-subtitle-generator)."
    )
    parser.add_argument("--video", required=True, help="Local video path")
    parser.add_argument("--out-dir", required=True, help="Output directory")
    parser.add_argument("--need-english", action="store_true")
    parser.add_argument("--need-chinese", action="store_true")
    parser.add_argument(
        "--en-in",
        default="",
        help="Existing English SRT when only Chinese is missing",
    )
    parser.add_argument("--model", default="base.en")
    parser.add_argument(
        "--engine",
        choices=("auto-subs", "whisper-subtitle-generator", "auto"),
        default="auto",
        help="ASR engine for missing English",
    )
    args = parser.parse_args()

    video = Path(args.video).expanduser().resolve()
    if not video.is_file():
        _fail(f"video not found: {video}")

    out_dir = Path(args.out_dir).expanduser().resolve()
    out_dir.mkdir(parents=True, exist_ok=True)

    need_en = bool(args.need_english)
    need_zh = bool(args.need_chinese)
    if not need_en and not need_zh:
        _fail("nothing to fill: pass --need-english and/or --need-chinese")

    en_path: Path | None = None
    zh_path: Path | None = None
    engine_used = None

    if need_en:
        target = out_dir / "en.auto.srt"
        engine = args.engine
        if engine in ("auto", "auto-subs"):
            try:
                en_path = _transcribe_english(video, target, args.model)
                engine_used = "auto-subs"
            except SystemExit:
                raise
            except Exception as exc:  # noqa: BLE001
                if engine == "auto-subs":
                    _fail(f"auto-subs failed: {exc}")
                en_path = None
        if en_path is None and engine in ("auto", "whisper-subtitle-generator"):
            alt = _maybe_translate_via_wsg_style(video, out_dir, args.model)
            if alt is None:
                _fail("whisper-subtitle-generator EN path failed")
            en_path = alt
            engine_used = "whisper-subtitle-generator"

    if need_zh and not need_en:
        # ZH-only: keep existing EN; App Dart side does EN→ZH MT.
        # We only validate / copy EN into out_dir so the bridge has a stable path.
        en_in = Path(args.en_in).expanduser() if args.en_in else None
        if en_in is None or not en_in.is_file():
            _fail("ZH-only fill requires --en-in with an existing English SRT")
        en_path = out_dir / "en.source.srt"
        en_path.write_text(en_in.read_text(encoding="utf-8", errors="ignore"), encoding="utf-8")
        engine_used = engine_used or "passthrough-en"
        # Signal to Dart that Chinese still needs MT.
        zh_path = None

    print(
        json.dumps(
            {
                "ok": True,
                "enPath": str(en_path) if en_path else None,
                "zhPath": str(zh_path) if zh_path else None,
                "engine": engine_used,
                "needChineseStill": bool(need_zh),
                "cwd": os.getcwd(),
            },
            ensure_ascii=False,
        )
    )


if __name__ == "__main__":
    main()
