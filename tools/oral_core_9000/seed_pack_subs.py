import json, re
from pathlib import Path

ROOT = Path(r"D:\AcquireEnglish\tools\oral_core_9000")
MANIFEST = ROOT / "manifest.json"
OUT = ROOT / "subs"

def ms_to_ts(ms: int) -> str:
    if ms < 0:
        ms = 0
    h = ms // 3600000
    m = (ms % 3600000) // 60000
    s = (ms % 60000) // 1000
    milli = ms % 1000
    return f"{h:02d}:{m:02d}:{s:02d},{milli:03d}"

def write_srt(path: Path, lines: list[str], duration_ms: int) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    cues = [ln.strip() for ln in lines if ln and ln.strip()]
    if not cues:
        cues = ["(no lines)"]
    # Leave a short lead-in, then evenly space cues.
    lead = min(3000, max(500, duration_ms // 20))
    usable = max(duration_ms - lead - 500, len(cues) * 2000)
    slot = usable // len(cues)
    slot = max(slot, 1800)
    chunks = []
    for i, text in enumerate(cues):
        start = lead + i * slot
        end = min(start + max(int(slot * 0.85), 1400), duration_ms)
        if end <= start:
            end = start + 1400
        chunks.append(f"{i+1}\n{ms_to_ts(start)} --> {ms_to_ts(end)}\n{text}\n")
    path.write_text("\n".join(chunks) + "\n", encoding="utf-8")

data = json.loads(MANIFEST.read_text(encoding="utf-8"))
n = 0
for lesson in data.get("lessons") or []:
    page = int(lesson.get("page") or lesson.get("lesson_no") or 0)
    if page <= 0:
        continue
    nn = f"{page:02d}"
    pack = lesson.get("pack") or {}
    duration = int(lesson.get("duration_ms") or 600000)
    en_lines = list(pack.get("shadow_lines") or [])
    if not en_lines:
        en_lines = list(pack.get("target_phrases") or [])
    if not en_lines:
        en_lines = [str(lesson.get("title") or f"Lesson {page}")]
    zh_lines = []
    for q in pack.get("quiz") or []:
        stem = str(q.get("stem") or "").strip()
        if re.search(r"[\u4e00-\u9fff]", stem):
            zh_lines.append(stem)
    if not zh_lines:
        title = str(lesson.get("title") or "")
        goal = str(lesson.get("goal") or "")
        zh_lines = [x for x in (title, goal) if x] or [f"第{page}课跟读"]
    # Align lengths roughly for bilingual timeline
    while len(zh_lines) < len(en_lines):
        zh_lines.append(zh_lines[-1])
    zh_lines = zh_lines[: len(en_lines)]
    write_srt(OUT / nn / "en.srt", en_lines, duration)
    write_srt(OUT / nn / "zh.srt", zh_lines, duration)
    n += 1
print(f"wrote {n} lessons under {OUT}")
