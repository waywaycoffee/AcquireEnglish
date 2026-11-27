"""Generate and cache a Mozilla.ai podcast on the local worker."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import wave


MODEL = "Qwen/Qwen2.5-1.5B-Instruct-GGUF/qwen2.5-1.5b-instruct-q8_0.gguf"
RECIPE = "mozilla-document-to-podcast-1.4.5-kokoro-default-voices-v1"
FORMATS = {".txt", ".md", ".pdf", ".docx", ".html"}


def ready(folder: Path) -> bool:
    try:
        if not (folder / "podcast.txt").read_text(encoding="utf-8").strip():
            return False
        with wave.open(str(folder / "podcast.wav"), "rb") as audio:
            return len(audio.readframes(1)) > 0
    except (OSError, ValueError, EOFError, wave.Error):
        return False


def generate(source: Path, cache: Path, engine: Path, *, offline: bool) -> Path:
    suffix = source.suffix.lower()
    if suffix not in FORMATS:
        raise ValueError(f"Unsupported source format: {suffix}")
    source_bytes = source.read_bytes()
    if not source_bytes:
        raise ValueError("Podcast source is empty")
    digest = hashlib.sha256(
        f"{RECIPE}\n{MODEL}\n{suffix}\n".encode() + source_bytes
    ).hexdigest()
    cache.mkdir(parents=True, exist_ok=True)
    target = cache / digest
    if ready(target):
        return target
    if target.exists():
        raise RuntimeError(f"Invalid cached output: {target}")

    env = {**os.environ, "PYTHONUTF8": "1"}
    if offline:
        env["HF_HUB_OFFLINE"] = "1"
    with tempfile.TemporaryDirectory(dir=cache) as temp:
        staging = Path(temp)
        material = staging / f"source{suffix}"
        material.write_bytes(source_bytes)
        output = staging / "output"
        subprocess.run(
            [
                str(engine.resolve()),
                "--input_file", str(material),
                "--output_folder", str(output),
                "--text_to_text_model", MODEL,
            ],
            env=env,
            check=True,
            timeout=1800,
        )
        if not ready(output):
            raise RuntimeError("Mozilla did not generate a playable WAV and script")
        try:
            output.rename(target)
        except OSError:
            if not ready(target):
                raise
    return target


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("--cache", type=Path, required=True)
    parser.add_argument("--engine", type=Path, required=True)
    parser.add_argument("--offline", action="store_true")
    args = parser.parse_args()
    output = generate(args.source, args.cache, args.engine, offline=args.offline)
    print(json.dumps({"audio": str(output / "podcast.wav"),
                      "script": str(output / "podcast.txt")}, ensure_ascii=False))


if __name__ == "__main__":
    main()
