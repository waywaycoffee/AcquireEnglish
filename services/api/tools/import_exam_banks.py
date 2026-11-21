"""Convert vendor exam banks into official ExamPack JSON under data/exam_packs/.

Reads caches in data/exam_bank_vendor/ (gitignored). Overwrites pack_*.json.
Audio extracted to exam_bank_vendor/_media_out/{family}/ for ECS upload.
"""

from __future__ import annotations

import json
import re
import shutil
import zipfile
from collections import defaultdict
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
VENDOR = ROOT / "data" / "exam_bank_vendor"
PACKS = ROOT / "data" / "exam_packs"
MEDIA_OUT = VENDOR / "_media_out"

META: dict[str, dict[str, Any]] = {
    "cet4": {
        "title": "大学英语四级备考包（全量题库）",
        "cefr": "B1",
        "mock": {"duration_minutes": 130, "sections": ["listening", "reading", "writing"]},
    },
    "cet6": {
        "title": "大学英语六级备考包（全量题库）",
        "cefr": "B2",
        "mock": {"duration_minutes": 130, "sections": ["listening", "reading", "writing"]},
    },
    "ielts_ac": {
        "title": "IELTS Academic Prep Pack",
        "cefr": "B2",
        "mock": {"duration_minutes": 150, "sections": ["listening", "reading", "writing"]},
    },
    "toefl": {
        "title": "TOEFL Prep Pack",
        "cefr": "B2",
        "mock": {"duration_minutes": 90, "sections": ["listening", "reading", "writing"]},
    },
    "gaokao": {
        "title": "高考英语备考包",
        "cefr": "B1",
        "mock": {"duration_minutes": 100, "sections": ["listening", "reading", "writing"]},
    },
    "zhongkao": {
        "title": "中考英语备考包",
        "cefr": "A2",
        "mock": {"duration_minutes": 90, "sections": ["listening", "reading", "writing"]},
    },
    "k12_general": {
        "title": "K12 英语通用备考包",
        "cefr": "A2",
        "mock": {"duration_minutes": 60, "sections": ["vocab", "reading", "writing"]},
    },
    "kaoyan": {
        "title": "考研英语备考包",
        "cefr": "B2",
        "mock": {"duration_minutes": 180, "sections": ["vocab", "reading", "writing"]},
    },
    "ket": {
        "title": "Cambridge KET/PET Prep Pack",
        "cefr": "A2",
        "mock": {"duration_minutes": 70, "sections": ["reading", "listening", "writing"]},
    },
}


def empty_sections() -> dict[str, list]:
    return {
        "vocab": [],
        "listening": [],
        "reading": [],
        "writing": [],
        "speaking": [],
    }


def mcq(pid: str, prompt: str, options: list[str], answer: str, explain: str = "") -> dict:
    return {
        "id": pid,
        "type": "mcq",
        "prompt": prompt,
        "options": options,
        "answer": answer,
        "explain": explain or "",
    }


def safe_id(raw: str) -> str:
    # No colons — Windows paths reject them (also keep URLs/ids filesystem-safe).
    s = re.sub(r"[^a-zA-Z0-9_\-.]+", "_", str(raw)).strip("._")
    return s[:120] or "item"


def merge_sections(dst: dict[str, list], src: dict[str, list]) -> None:
    seen: dict[str, set[str]] = defaultdict(set)
    for skill, items in dst.items():
        for it in items:
            if isinstance(it, dict) and it.get("id"):
                seen[skill].add(str(it["id"]))
    for skill, items in src.items():
        bucket = dst.setdefault(skill, [])
        for it in items:
            if not isinstance(it, dict):
                continue
            iid = str(it.get("id") or "")
            if iid and iid in seen[skill]:
                continue
            if iid:
                seen[skill].add(iid)
            bucket.append(it)


def load_base_pack(family: str) -> dict[str, list]:
    path = PACKS / f"pack_{family}.json"
    sections = empty_sections()
    if not path.is_file():
        return sections
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return sections
    raw = data.get("sections") or {}
    for skill in sections:
        items = raw.get(skill) or []
        if isinstance(items, list):
            sections[skill] = [x for x in items if isinstance(x, dict)]
    return sections


def option_text(opt: Any) -> str:
    if isinstance(opt, dict):
        return str(opt.get("content") or opt.get("text") or opt.get("label") or opt)
    if isinstance(opt, (list, tuple)) and len(opt) >= 2:
        return str(opt[1])
    return str(opt)


def answer_from_index(options: list[str], idx: Any) -> str:
    try:
        i = int(idx)
    except (TypeError, ValueError):
        # letter A/B/C
        if isinstance(idx, str) and idx.strip().upper() in "ABCDEFGH":
            i = ord(idx.strip().upper()) - ord("A")
        else:
            return str(idx)
    if 0 <= i < len(options):
        return options[i]
    return str(idx)


# ---------- ESQ (CET / kaoyan) ----------


def convert_esq(
    esq_path: Path,
    family: str,
    *,
    extract_audio: bool = True,
    max_papers: int | None = None,
) -> dict[str, list]:
    out = empty_sections()
    if not esq_path.is_file():
        print("skip missing esq", esq_path)
        return out
    media_dir = MEDIA_OUT / family
    if extract_audio:
        media_dir.mkdir(parents=True, exist_ok=True)

    with zipfile.ZipFile(esq_path) as zf:
        papers = sorted(
            n for n in zf.namelist() if n.startswith("papers/") and n.endswith(".json")
        )
        if max_papers:
            papers = papers[:max_papers]
        answers_map: dict[str, dict[str, Any]] = {}
        for n in zf.namelist():
            if n.startswith("answers/") and n.endswith(".json"):
                try:
                    raw = json.loads(zf.read(n))
                except json.JSONDecodeError:
                    continue
                ans = raw.get("answers")
                if isinstance(ans, list):
                    for pair in ans:
                        if isinstance(pair, (list, tuple)) and len(pair) >= 2:
                            answers_map[str(pair[0])] = pair[1] if isinstance(pair[1], dict) else {"correctOption": pair[1]}
                elif isinstance(ans, dict):
                    for k, v in ans.items():
                        answers_map[str(k)] = v if isinstance(v, dict) else {"correctOption": v}

        audio_by_stem: dict[str, str] = {}
        for n in zf.namelist():
            if n.startswith("assets/audio/") and n.lower().endswith(".mp3"):
                # assets/audio/0001-hash.mp3 → stem 0001
                base = Path(n).name
                stem = base.split("-", 1)[0]
                audio_by_stem[stem] = n

        for paper_name in papers:
            stem = Path(paper_name).stem  # 0001
            try:
                paper = json.loads(zf.read(paper_name))
            except json.JSONDecodeError:
                continue
            title = str(paper.get("title") or paper.get("paperKey") or stem)
            paper_key = safe_id(paper.get("paperKey") or f"{family}_{stem}")
            audio_url = ""
            audio_member = audio_by_stem.get(stem)
            if audio_member and extract_audio:
                dest_name = f"{paper_key}.mp3"
                dest = media_dir / dest_name
                if not dest.exists():
                    with zf.open(audio_member) as src, open(dest, "wb") as dst:
                        shutil.copyfileobj(src, dst)
                audio_url = f"/media/exam/{family}/{dest_name}"

            for unit in paper.get("units") or []:
                if not isinstance(unit, dict):
                    continue
                utype = str(unit.get("type") or "")
                subtype = str(unit.get("subtype") or "")
                unit_title = str(unit.get("title") or subtype or utype)
                passage = str(unit.get("passage") or unit.get("script") or unit.get("transcript") or "")
                questions = unit.get("questions") or []
                mcqs: list[dict] = []
                for q in questions:
                    if not isinstance(q, dict):
                        continue
                    qid = safe_id(q.get("questionKey") or q.get("id") or f"{paper_key}_{q.get('number')}")
                    opts_raw = q.get("options") or []
                    options = [option_text(o) for o in opts_raw]
                    if not options:
                        # cloze / fill without options → skip or writing
                        continue
                    ans_meta = answers_map.get(str(q.get("questionKey") or ""), {})
                    correct = ans_meta.get("correctOption") or ans_meta.get("answer") or q.get("answer")
                    if isinstance(correct, str) and len(correct) == 1 and correct.upper() in "ABCDEFGH":
                        answer = answer_from_index(options, correct)
                    elif isinstance(correct, int):
                        answer = answer_from_index(options, correct)
                    else:
                        # match by option key
                        answer = ""
                        for o in opts_raw:
                            if isinstance(o, dict) and str(o.get("key") or "").upper() == str(correct or "").upper():
                                answer = option_text(o)
                                break
                        if not answer:
                            answer = answer_from_index(options, correct) if correct is not None else options[0]
                    prompt = str(q.get("stem") or q.get("question") or q.get("prompt") or f"Q{q.get('number')}")
                    explain = str(ans_meta.get("explain") or ans_meta.get("analysis") or "")
                    item = mcq(qid, prompt, options, answer, explain)
                    mcqs.append(item)
                    # also seed vocab from first option lines when word_bank
                    if utype in {"word_bank", "vocab"}:
                        out["vocab"].append(item)

                uid = safe_id(f"{paper_key}_{utype}_{subtype}_{unit.get('sequence') or unit_title}")
                if utype == "listening" or "listen" in subtype.lower():
                    out["listening"].append(
                        {
                            "id": uid,
                            "type": "listening",
                            "title": f"{title} · {unit_title}",
                            "script": passage[:8000],
                            "audio_url": audio_url,
                            "questions": mcqs,
                        }
                    )
                elif utype in {"reading", "paragraph_matching", "word_bank"} or "read" in subtype.lower():
                    out["reading"].append(
                        {
                            "id": uid,
                            "type": "reading",
                            "title": f"{title} · {unit_title}",
                            "passage": passage[:12000] or unit_title,
                            "questions": mcqs,
                        }
                    )
                elif utype in {"writing", "translation"}:
                    prompt = passage or unit_title
                    for q in questions:
                        if isinstance(q, dict):
                            prompt = str(q.get("stem") or q.get("prompt") or prompt)
                            break
                    out["writing"].append(
                        {
                            "id": uid,
                            "type": "writing",
                            "prompt": prompt[:4000],
                            "rubric": "cet" if family.startswith("cet") else "generic",
                            "min_words": 120 if family.startswith("cet") else 150,
                        }
                    )
                elif mcqs:
                    # fallback: treat as reading
                    out["reading"].append(
                        {
                            "id": uid,
                            "type": "reading",
                            "title": f"{title} · {unit_title}",
                            "passage": passage[:12000] or unit_title,
                            "questions": mcqs,
                        }
                    )
    print(
        f"ESQ {esq_path.name} → {family}: "
        f"L{len(out['listening'])} R{len(out['reading'])} V{len(out['vocab'])} W{len(out['writing'])}"
    )
    return out


# ---------- Fluova (TOEFL) ----------


def convert_fluova(root: Path) -> dict[str, list]:
    out = empty_sections()
    bank = root / "content" / "bank" / "units"
    if not bank.is_dir():
        print("skip fluova (no bank)")
        return out
    for path in bank.rglob("*.json"):
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            continue
        rel = path.relative_to(bank).as_posix()
        task = str(data.get("task") or path.parent.name)
        uid = safe_id(data.get("id") or path.stem)
        screen = data.get("screen") or {}
        if not isinstance(screen, dict):
            screen = {}
        text_parts = screen.get("text") or data.get("text") or []
        if isinstance(text_parts, list):
            passage = "\n".join(re.sub(r"<[^>]+>", "", str(t)) for t in text_parts)
        else:
            passage = re.sub(r"<[^>]+>", "", str(text_parts))
        title = str(screen.get("title") or data.get("topic") or path.stem)
        questions = screen.get("questions") or data.get("questions") or []
        mcqs: list[dict] = []
        for q in questions:
            if not isinstance(q, dict):
                continue
            opts = [str(o) for o in (q.get("options") or [])]
            if not opts:
                continue
            ans = answer_from_index(opts, q.get("answer"))
            why = q.get("why") or {}
            explain = ""
            if isinstance(why, dict):
                explain = str(why.get("en") or why.get("zh") or "")
            else:
                explain = str(why)
            mcqs.append(
                mcq(
                    safe_id(q.get("id") or f"{uid}_q"),
                    str(q.get("stem") or q.get("question") or "Question"),
                    opts,
                    ans,
                    explain,
                )
            )
        # writing / speaking prompts
        if "writing" in rel or task in {"email", "discussion", "build_sentence", "essay"}:
            prompt = passage or title
            if data.get("prompt"):
                prompt = str(data["prompt"])
            out["writing"].append(
                {
                    "id": uid,
                    "type": "writing",
                    "prompt": prompt[:4000],
                    "rubric": "generic",
                    "min_words": 100,
                }
            )
            if mcqs:
                out["vocab"].extend(mcqs[:3])
            continue
        if "speaking" in rel or task in {"interview", "listen_repeat"}:
            out["speaking"].append(
                {
                    "id": uid,
                    "type": "speaking",
                    "prompt": passage or title,
                    "tips": str(data.get("topic") or task),
                }
            )
            continue
        if "listening" in rel or task in {"conversation", "lecture", "announcement", "choose_response"}:
            out["listening"].append(
                {
                    "id": uid,
                    "type": "listening",
                    "title": title,
                    "script": passage[:8000],
                    "audio_url": "",
                    "questions": mcqs,
                }
            )
        else:
            out["reading"].append(
                {
                    "id": uid,
                    "type": "reading",
                    "title": title,
                    "passage": passage[:12000] or title,
                    "questions": mcqs,
                }
            )
            out["vocab"].extend(mcqs[:1])
    print(
        f"fluova → toefl: L{len(out['listening'])} R{len(out['reading'])} "
        f"W{len(out['writing'])} S{len(out['speaking'])}"
    )
    return out


# ---------- Pteracai ----------


def convert_pteracai(bank_json: Path, test_key: str) -> dict[str, list]:
    out = empty_sections()
    if not bank_json.is_file():
        return out
    data = json.loads(bank_json.read_text(encoding="utf-8"))
    tests = (data.get("tests") or {}).get(test_key) or {}
    questions = tests.get("questions") or []
    for q in questions:
        if not isinstance(q, dict):
            continue
        section = str(q.get("section") or "reading").lower()
        qid = safe_id(q.get("id") or f"{test_key}_{len(out['reading'])}")
        opts = [str(o) for o in (q.get("options") or [])]
        passage = str(q.get("passage") or "")
        prompt = str(q.get("question") or q.get("prompt") or "Question")
        explain = str(q.get("explanation") or q.get("trap") or "")
        answer = ""
        if opts:
            answer = answer_from_index(opts, q.get("answer"))
            item = mcq(qid, prompt, opts, answer, explain)
        else:
            item = None
        if section in {"writing"}:
            out["writing"].append(
                {
                    "id": qid,
                    "type": "writing",
                    "prompt": (passage + "\n" + prompt).strip()[:4000],
                    "rubric": "ielts" if test_key == "ielts" else "generic",
                    "min_words": 150,
                }
            )
        elif section in {"speaking"}:
            out["speaking"].append(
                {"id": qid, "type": "speaking", "prompt": prompt, "tips": explain[:500]}
            )
        elif section in {"listening"}:
            qs = [item] if item else []
            out["listening"].append(
                {
                    "id": qid,
                    "type": "listening",
                    "title": str(q.get("topic") or "Listening"),
                    "script": passage[:8000],
                    "audio_url": "",
                    "questions": qs,
                }
            )
        else:
            qs = [item] if item else []
            if item and not passage:
                out["vocab"].append(item)
            else:
                out["reading"].append(
                    {
                        "id": qid + "_r",
                        "type": "reading",
                        "title": str(q.get("topic") or "Reading"),
                        "passage": passage[:12000] or prompt,
                        "questions": qs,
                    }
                )
                if item:
                    out["vocab"].append(item)
    print(f"pteracai {test_key}: R{len(out['reading'])} L{len(out['listening'])} V{len(out['vocab'])}")
    return out


# ---------- ExpressAI Gaokao ----------


def convert_expressai(root: Path) -> dict[str, list]:
    out = empty_sections()
    if not root.is_dir():
        return out
    for year_dir in sorted(root.iterdir()):
        if not year_dir.is_dir() or year_dir.name.startswith("."):
            continue
        prefix = safe_id(year_dir.name)
        for skill_file, skill in (
            ("listening.json", "listening"),
            ("processed_listening.json", "listening"),
            ("reading.json", "reading"),
            ("cloze.json", "reading"),
            ("writing.json", "writing"),
        ):
            path = year_dir / skill_file
            if not path.is_file():
                continue
            try:
                blocks = json.loads(path.read_text(encoding="utf-8"))
            except json.JSONDecodeError:
                continue
            if not isinstance(blocks, list):
                continue
            for bi, block in enumerate(blocks):
                if not isinstance(block, dict):
                    continue
                qtype = str(block.get("question_type") or "")
                contents = block.get("content") or []
                if skill == "writing" or qtype in {"writing", "writing-essay", "reading-writing"}:
                    prompt = str(block.get("description") or block.get("name") or "")
                    if isinstance(contents, list) and contents:
                        c0 = contents[0]
                        if isinstance(c0, dict):
                            prompt = str(c0.get("context") or c0.get("question") or prompt)
                        else:
                            prompt = str(c0)
                    out["writing"].append(
                        {
                            "id": f"{prefix}_w_{bi}",
                            "type": "writing",
                            "prompt": prompt[:4000],
                            "rubric": "k12",
                            "min_words": 100,
                        }
                    )
                    continue
                if not isinstance(contents, list):
                    continue
                for ci, content in enumerate(contents):
                    if not isinstance(content, dict):
                        continue
                    passage = str(content.get("context") or "")
                    qs = []
                    for q in content.get("questions") or []:
                        if not isinstance(q, dict):
                            continue
                        opts = [str(o) for o in (q.get("options") or [])]
                        if not opts:
                            continue
                        ans = answer_from_index(opts, q.get("answer"))
                        qs.append(
                            mcq(
                                safe_id(f"{prefix}_{q.get('question_id')}_{ci}"),
                                str(q.get("question") or "Question"),
                                opts,
                                ans,
                            )
                        )
                    uid = f"{prefix}_{skill}_{bi}_{ci}"
                    if skill == "listening":
                        out["listening"].append(
                            {
                                "id": uid,
                                "type": "listening",
                                "title": str(block.get("name") or year_dir.name),
                                "script": passage[:8000],
                                "audio_url": "",
                                "questions": qs,
                            }
                        )
                    else:
                        out["reading"].append(
                            {
                                "id": uid,
                                "type": "reading",
                                "title": str(block.get("name") or year_dir.name),
                                "passage": passage[:12000] or str(block.get("name") or "Passage"),
                                "questions": qs,
                            }
                        )
                        out["vocab"].extend(qs[:2])
    print(f"ExpressAI → gaokao: L{len(out['listening'])} R{len(out['reading'])} W{len(out['writing'])}")
    return out


# ---------- Gongyining CET4 JS banks ----------


def convert_gongyining(root: Path) -> dict[str, list]:
    out = empty_sections()
    bank = root / "bank"
    if not bank.is_dir():
        return out
    for path in sorted(bank.glob("cet4-*.js")):
        text = path.read_text(encoding="utf-8", errors="ignore")
        m = re.search(r"\.push\((\{.*\})\s*\);?\s*$", text, re.S)
        if not m:
            # find first { after push
            idx = text.find(".push(")
            if idx < 0:
                continue
            blob = text[idx + 5 :]
            try:
                data, _ = json.JSONDecoder().raw_decode(blob.lstrip().lstrip("("))
            except json.JSONDecodeError:
                continue
        else:
            try:
                data = json.loads(m.group(1))
            except json.JSONDecodeError:
                continue
        if not isinstance(data, dict):
            continue
        pid = safe_id(data.get("id") or path.stem)
        title = str(data.get("source") or path.stem)
        writing = data.get("writing") or {}
        if isinstance(writing, dict) and writing.get("prompt"):
            out["writing"].append(
                {
                    "id": f"{pid}_w",
                    "type": "writing",
                    "prompt": str(writing["prompt"])[:4000],
                    "rubric": "cet",
                    "min_words": 120,
                }
            )
        translation = data.get("translation") or {}
        if isinstance(translation, dict) and (translation.get("prompt") or translation.get("source")):
            out["writing"].append(
                {
                    "id": f"{pid}_tr",
                    "type": "writing",
                    "prompt": "Translate into English:\n"
                    + str(translation.get("source") or translation.get("prompt"))[:3500],
                    "rubric": "cet",
                    "min_words": 60,
                }
            )
        # reading / listening sections if present as structured fields
        for key, skill in (("listening", "listening"), ("reading", "reading")):
            block = data.get(key)
            if not isinstance(block, dict):
                continue
            # common shapes: sections list or passages
            sections = block.get("sections") or block.get("parts") or []
            if isinstance(block.get("passages"), list):
                sections = block["passages"]
            if not sections and block.get("questions"):
                sections = [block]
            for si, sec in enumerate(sections if isinstance(sections, list) else []):
                if not isinstance(sec, dict):
                    continue
                passage = str(
                    sec.get("passage")
                    or sec.get("script")
                    or sec.get("transcript")
                    or sec.get("text")
                    or ""
                )
                qs = []
                for q in sec.get("questions") or []:
                    if not isinstance(q, dict):
                        continue
                    opts = [option_text(o) for o in (q.get("options") or [])]
                    if len(opts) < 2:
                        continue
                    ans = answer_from_index(opts, q.get("answer") if "answer" in q else q.get("correct"))
                    qs.append(
                        mcq(
                            safe_id(q.get("id") or f"{pid}_{key}_{si}_{len(qs)}"),
                            str(q.get("stem") or q.get("question") or "Question"),
                            opts,
                            ans,
                            str(q.get("explain") or q.get("analysis") or ""),
                        )
                    )
                uid = f"{pid}_{key}_{si}"
                if skill == "listening":
                    out["listening"].append(
                        {
                            "id": uid,
                            "type": "listening",
                            "title": f"{title} listening",
                            "script": passage[:8000],
                            "audio_url": "",
                            "questions": qs,
                        }
                    )
                else:
                    out["reading"].append(
                        {
                            "id": uid,
                            "type": "reading",
                            "title": f"{title} reading",
                            "passage": passage[:12000] or title,
                            "questions": qs,
                        }
                    )
    print(
        f"gongyining → cet4: L{len(out['listening'])} R{len(out['reading'])} W{len(out['writing'])}"
    )
    return out


# ---------- toefl-ielts-prep JS data (best-effort) ----------


def _extract_js_array(text: str, var_name: str) -> list[Any]:
    """Extract window.VAR = [ ... ]; using balanced brackets + json5-ish cleanup."""
    m = re.search(rf"window\.{re.escape(var_name)}\s*=\s*\[", text)
    if not m:
        return []
    start = m.end() - 1
    depth = 0
    i = start
    while i < len(text):
        ch = text[i]
        if ch == "[":
            depth += 1
        elif ch == "]":
            depth -= 1
            if depth == 0:
                blob = text[start : i + 1]
                # JS → JSON-ish
                blob2 = re.sub(r"(\w+)\s*:", r'"\1":', blob)  # naive key quote — may break
                # Better: use node if available
                return _parse_js_literal(blob)
        i += 1
    return []


def _parse_js_literal(blob: str) -> list[Any]:
    node = shutil.which("node")
    if node:
        import subprocess
        import tempfile

        script = "const x = " + blob + "; process.stdout.write(JSON.stringify(x));"
        with tempfile.NamedTemporaryFile("w", suffix=".js", delete=False, encoding="utf-8") as f:
            f.write(script)
            tmp = f.name
        try:
            proc = subprocess.run(
                [node, tmp],
                capture_output=True,
                text=True,
                encoding="utf-8",
                timeout=60,
            )
            if proc.returncode == 0 and proc.stdout:
                data = json.loads(proc.stdout)
                return data if isinstance(data, list) else []
        except (OSError, json.JSONDecodeError, subprocess.TimeoutExpired):
            pass
        finally:
            Path(tmp).unlink(missing_ok=True)
    return []


def convert_toefl_ielts_prep(root: Path) -> tuple[dict[str, list], dict[str, list]]:
    ielts = empty_sections()
    toefl = empty_sections()
    js_dir = root / "js"
    if not js_dir.is_dir():
        return ielts, toefl

    mapping = [
        ("ielts-reading-data.js", "IELTS_READING", "reading", ielts),
        ("ielts-listening-data.js", "IELTS_LISTENING", "listening", ielts),
        ("ielts-writing-data.js", "IELTS_WRITING", "writing", ielts),
        ("ielts-speaking-data.js", "IELTS_SPEAKING", "speaking", ielts),
    ]
    # also discover toefl data files
    for path in js_dir.glob("*-data.js"):
        name = path.name.lower()
        if name.startswith("ielts"):
            continue
        if "toefl" in name or "reading" in name or "listening" in name:
            text = path.read_text(encoding="utf-8", errors="ignore")
            m = re.search(r"window\.([A-Z0-9_]+)\s*=\s*\[", text)
            if not m:
                continue
            arr = _extract_js_array(text, m.group(1))
            skill = "reading"
            if "listen" in name:
                skill = "listening"
            elif "writ" in name:
                skill = "writing"
            elif "speak" in name:
                skill = "speaking"
            _ingest_tip_array(arr, skill, toefl, prefix=path.stem)

    for fname, var, skill, target in mapping:
        path = js_dir / fname
        if not path.is_file():
            continue
        text = path.read_text(encoding="utf-8", errors="ignore")
        arr = _extract_js_array(text, var)
        _ingest_tip_array(arr, skill, target, prefix=var.lower())
        print(f"toefl-ielts-prep {var}: {skill} items parsed={len(arr)}")
    return ielts, toefl


def _ingest_tip_array(arr: list[Any], skill: str, target: dict[str, list], prefix: str) -> None:
    for i, item in enumerate(arr):
        if not isinstance(item, dict):
            continue
        uid = safe_id(item.get("id") or f"{prefix}_{i}")
        title = str(item.get("title") or item.get("topic") or uid)
        # reading with paras
        paras = item.get("paras") or item.get("passage") or item.get("text")
        if isinstance(paras, list):
            bits = []
            for p in paras:
                if isinstance(p, (list, tuple)) and len(p) >= 2:
                    bits.append(f"{p[0]}. {p[1]}")
                else:
                    bits.append(str(p))
            passage = "\n".join(bits)
        else:
            passage = str(paras or "")
        groups = item.get("groups") or item.get("questions") or item.get("qs") or []
        mcqs: list[dict] = []
        if isinstance(groups, list):
            for g in groups:
                if not isinstance(g, dict):
                    continue
                # group may nest questions
                nested = g.get("qs") or g.get("questions") or [g]
                for q in nested:
                    if not isinstance(q, dict):
                        continue
                    opts_raw = q.get("options") or q.get("o") or []
                    opts = []
                    for o in opts_raw:
                        if isinstance(o, (list, tuple)) and len(o) >= 2:
                            opts.append(str(o[1]))
                        else:
                            opts.append(str(o))
                    if len(opts) < 2:
                        continue
                    ans = q.get("a") if "a" in q else q.get("answer")
                    if isinstance(ans, list):
                        ans = ans[0] if ans else 0
                    answer = answer_from_index(opts, ans)
                    mcqs.append(
                        mcq(
                            safe_id(q.get("id") or f"{uid}_{len(mcqs)}"),
                            str(q.get("q") or q.get("stem") or q.get("question") or "Question"),
                            opts,
                            answer,
                        )
                    )
        if skill == "writing":
            prompt = str(item.get("prompt") or item.get("task") or passage or title)
            target["writing"].append(
                {
                    "id": uid,
                    "type": "writing",
                    "prompt": prompt[:4000],
                    "rubric": "ielts",
                    "min_words": int(item.get("minWords") or 150),
                }
            )
        elif skill == "speaking":
            target["speaking"].append(
                {
                    "id": uid,
                    "type": "speaking",
                    "prompt": str(item.get("prompt") or item.get("q") or title),
                    "tips": str(item.get("tips") or item.get("notes") or ""),
                }
            )
        elif skill == "listening":
            target["listening"].append(
                {
                    "id": uid,
                    "type": "listening",
                    "title": title,
                    "script": passage[:8000],
                    "audio_url": "",
                    "questions": mcqs,
                }
            )
        else:
            target["reading"].append(
                {
                    "id": uid,
                    "type": "reading",
                    "title": title,
                    "passage": passage[:12000] or title,
                    "questions": mcqs,
                }
            )
            target["vocab"].extend(mcqs[:2])


# ---------- Gaokao 2026 HTML ----------


def convert_gaokao_2026_html(path: Path) -> dict[str, list]:
    out = empty_sections()
    if not path.is_file():
        return out
    html = path.read_text(encoding="utf-8", errors="ignore")
    # Extract passages and questions heuristically from embedded JSON if present
    m = re.search(r"(?:const|var|let)\s+EXAM\s*=\s*(\{.*?\});", html, re.S)
    if not m:
        m = re.search(r"questions\s*:\s*(\[.*?\])\s*[,}]", html, re.S)
    data = None
    if m:
        blob = m.group(1)
        try:
            data = json.loads(blob)
        except json.JSONDecodeError:
            data = _parse_js_literal(blob) if blob.strip().startswith("[") else None
            if isinstance(data, list):
                data = {"questions": data}
    if isinstance(data, dict):
        questions = data.get("questions") or data.get("items") or []
        passage = str(data.get("passage") or data.get("text") or "2026 Gaokao English Reading")
        mcqs = []
        for q in questions if isinstance(questions, list) else []:
            if not isinstance(q, dict):
                continue
            opts = [str(o) for o in (q.get("options") or [])]
            if len(opts) < 2:
                continue
            mcqs.append(
                mcq(
                    safe_id(q.get("id") or f"gk2026_{len(mcqs)}"),
                    str(q.get("stem") or q.get("question") or "Question"),
                    opts,
                    answer_from_index(opts, q.get("answer")),
                )
            )
        if mcqs:
            out["reading"].append(
                {
                    "id": "gaokao_2026_reading",
                    "type": "reading",
                    "title": "2026 高考英语阅读",
                    "passage": passage[:12000],
                    "questions": mcqs,
                }
            )
    print(f"gaokao2026: R{len(out['reading'])}")
    return out


# ---------- SmartGaokao junior/primary english ----------


def convert_smart_gaokao(root: Path) -> tuple[dict[str, list], dict[str, list], dict[str, list]]:
    gaokao = empty_sections()
    zhongkao = empty_sections()
    k12 = empty_sections()
    if not root.is_dir():
        return gaokao, zhongkao, k12

    # GAOKAO-Bench json if vendored
    bench = root / "data" / "gaokao_bench"
    if bench.is_dir():
        for path in bench.rglob("*.json"):
            if "english" not in path.name.lower() and "English" not in path.as_posix():
                # still try files under english folders
                if "english" not in path.as_posix().lower():
                    continue
            try:
                data = json.loads(path.read_text(encoding="utf-8"))
            except (OSError, json.JSONDecodeError):
                continue
            items = data if isinstance(data, list) else data.get("questions") or data.get("example") or []
            if isinstance(data, dict) and not items:
                # single question style
                items = [data]
            for i, q in enumerate(items if isinstance(items, list) else []):
                if not isinstance(q, dict):
                    continue
                opts = q.get("options") or q.get("choices") or []
                if isinstance(opts, dict):
                    opts = [f"{k}. {v}" for k, v in opts.items()]
                opts = [str(o) for o in opts]
                question = str(q.get("question") or q.get("stem") or q.get("prompt") or "")
                if len(opts) >= 2:
                    ans = q.get("answer")
                    if isinstance(ans, list):
                        ans = ans[0] if ans else 0
                    item = mcq(
                        safe_id(f"sg_{path.stem}_{i}"),
                        question[:800] or "Question",
                        opts,
                        answer_from_index(opts, ans),
                        str(q.get("analysis") or q.get("explanation") or ""),
                    )
                    gaokao["vocab"].append(item)
                    gaokao["reading"].append(
                        {
                            "id": safe_id(f"sg_r_{path.stem}_{i}"),
                            "type": "reading",
                            "title": path.stem,
                            "passage": question[:4000],
                            "questions": [item],
                        }
                    )

    junior = root / "data" / "junior"
    if junior.is_dir():
        for path in junior.rglob("*.json"):
            if "english" not in path.as_posix().lower() and "英" not in path.read_text(
                encoding="utf-8", errors="ignore"
            )[:200]:
                # still load question-like files
                pass
            try:
                data = json.loads(path.read_text(encoding="utf-8"))
            except (OSError, json.JSONDecodeError):
                continue
            _ingest_smart_generic(data, zhongkao, prefix=f"zk_{path.stem}")

    primary = root / "data" / "primary"
    if primary.is_dir():
        for path in primary.rglob("*.json"):
            if "english" not in path.as_posix().lower() and "en" not in path.name.lower():
                continue
            try:
                data = json.loads(path.read_text(encoding="utf-8"))
            except (OSError, json.JSONDecodeError):
                continue
            _ingest_smart_generic(data, k12, prefix=f"k12_{path.stem}")

    print(
        f"SmartGaokao: gaokao V{len(gaokao['vocab'])} | zhongkao R{len(zhongkao['reading'])} | k12 R{len(k12['reading'])}"
    )
    return gaokao, zhongkao, k12


def _ingest_smart_generic(data: Any, target: dict[str, list], prefix: str) -> None:
    items: list[Any]
    if isinstance(data, list):
        items = data
    elif isinstance(data, dict):
        items = data.get("questions") or data.get("items") or data.get("exercises") or [data]
    else:
        return
    for i, q in enumerate(items):
        if not isinstance(q, dict):
            continue
        opts = q.get("options") or q.get("choices") or []
        if isinstance(opts, dict):
            opts = list(opts.values())
        opts = [str(o) for o in opts]
        stem = str(q.get("question") or q.get("stem") or q.get("content") or q.get("prompt") or "")
        if len(opts) >= 2 and stem:
            item = mcq(
                safe_id(f"{prefix}_{i}"),
                stem[:800],
                opts,
                answer_from_index(opts, q.get("answer") or q.get("key")),
                str(q.get("analysis") or q.get("explanation") or ""),
            )
            target["vocab"].append(item)
            target["reading"].append(
                {
                    "id": safe_id(f"{prefix}_r_{i}"),
                    "type": "reading",
                    "title": prefix,
                    "passage": stem[:4000],
                    "questions": [item],
                }
            )
        elif stem and ("write" in str(q.get("type") or "").lower() or q.get("prompt")):
            target["writing"].append(
                {
                    "id": safe_id(f"{prefix}_w_{i}"),
                    "type": "writing",
                    "prompt": stem[:4000],
                    "rubric": "k12",
                    "min_words": 60,
                }
            )


# ---------- IELTS AI dataset ----------


def convert_ielts_ai(root: Path) -> dict[str, list]:
    out = empty_sections()
    if not root.is_dir():
        return out
    # zipball may nest one folder
    bases = [root]
    kids = [p for p in root.iterdir() if p.is_dir() and not p.name.startswith(".")]
    if len(kids) == 1 and not (root / "practice-drills").exists():
        bases = [kids[0]]
    media_dir = MEDIA_OUT / "ielts_ac"
    media_dir.mkdir(parents=True, exist_ok=True)

    for base in bases:
        for path in base.rglob("*.json"):
            if path.name.lower() in {"manifest.json", "package.json"}:
                # listening manifest
                try:
                    man = json.loads(path.read_text(encoding="utf-8"))
                except json.JSONDecodeError:
                    continue
                if isinstance(man, dict) and (man.get("sections") or man.get("questions")):
                    uid = safe_id(path.parent.name)
                    script_parts = []
                    qs = []
                    for sec in man.get("sections") or []:
                        if isinstance(sec, dict):
                            script_parts.append(str(sec.get("transcript") or sec.get("script") or ""))
                            for q in sec.get("questions") or []:
                                if not isinstance(q, dict):
                                    continue
                                opts = [str(o) for o in (q.get("options") or [])]
                                if len(opts) < 2:
                                    continue
                                qs.append(
                                    mcq(
                                        safe_id(q.get("id") or f"{uid}_{len(qs)}"),
                                        str(q.get("question") or q.get("prompt") or "Q"),
                                        opts,
                                        answer_from_index(opts, q.get("answer")),
                                    )
                                )
                    # copy mp3s beside manifest
                    audio_url = ""
                    mp3s = sorted(path.parent.glob("*.mp3"))
                    if mp3s:
                        dest = media_dir / f"{uid}.mp3"
                        if not dest.exists():
                            shutil.copy2(mp3s[0], dest)
                        audio_url = f"/media/exam/ielts_ac/{uid}.mp3"
                    out["listening"].append(
                        {
                            "id": uid,
                            "type": "listening",
                            "title": path.parent.name,
                            "script": "\n".join(script_parts)[:8000],
                            "audio_url": audio_url,
                            "questions": qs,
                        }
                    )
                continue
            try:
                data = json.loads(path.read_text(encoding="utf-8"))
            except json.JSONDecodeError:
                continue
            if not isinstance(data, dict):
                continue
            uid = safe_id(data.get("id") or path.stem)
            # reading
            if "passage" in data or "passages" in data or "reading" in path.as_posix().lower():
                passage = data.get("passage") or ""
                if not passage and isinstance(data.get("passages"), list):
                    passage = "\n\n".join(str(p) for p in data["passages"])
                qs = []
                for q in data.get("questions") or []:
                    if not isinstance(q, dict):
                        continue
                    opts = [str(o) for o in (q.get("options") or [])]
                    if len(opts) < 2:
                        continue
                    qs.append(
                        mcq(
                            safe_id(q.get("id") or f"{uid}_{len(qs)}"),
                            str(q.get("question") or q.get("prompt") or "Q"),
                            opts,
                            answer_from_index(opts, q.get("answer")),
                        )
                    )
                out["reading"].append(
                    {
                        "id": uid,
                        "type": "reading",
                        "title": str(data.get("title") or path.stem),
                        "passage": str(passage)[:12000],
                        "questions": qs,
                    }
                )
            if "writing" in path.as_posix().lower() or data.get("task"):
                prompt = str(
                    data.get("prompt")
                    or data.get("task")
                    or data.get("question")
                    or ""
                )
                if prompt:
                    out["writing"].append(
                        {
                            "id": uid + "_w",
                            "type": "writing",
                            "prompt": prompt[:4000],
                            "rubric": "ielts",
                            "min_words": 150,
                        }
                    )
    print(f"ielts-ai: L{len(out['listening'])} R{len(out['reading'])} W{len(out['writing'])}")
    return out


# ---------- structured kaoyan ----------


def convert_structured_kaoyan(root: Path) -> dict[str, list]:
    out = empty_sections()
    if not root.is_dir():
        return out
    data_root = root / "data"
    if not data_root.is_dir():
        # nested zip folder
        kids = [p for p in root.iterdir() if p.is_dir()]
        for k in kids:
            if (k / "data").is_dir():
                data_root = k / "data"
                break
    if not data_root.is_dir():
        return out
    for year_dir in sorted(data_root.iterdir()):
        if not year_dir.is_dir():
            continue
        for path in year_dir.glob("*.json"):
            if path.name == "index.json":
                continue
            try:
                data = json.loads(path.read_text(encoding="utf-8"))
            except json.JSONDecodeError:
                continue
            sections = data if isinstance(data, list) else [data]
            for block in sections:
                if not isinstance(block, dict):
                    continue
                # common structured fields
                passage = str(block.get("passage") or block.get("text") or block.get("article") or "")
                title = str(block.get("title") or path.stem)
                qs = []
                for q in block.get("questions") or block.get("items") or []:
                    if not isinstance(q, dict):
                        continue
                    opts = q.get("options") or []
                    if isinstance(opts, dict):
                        opts = [f"{k}. {v}" for k, v in opts.items()]
                    opts = [str(o) for o in opts]
                    if len(opts) < 2:
                        continue
                    qs.append(
                        mcq(
                            safe_id(q.get("id") or f"{year_dir.name}_{path.stem}_{len(qs)}"),
                            str(q.get("stem") or q.get("question") or "Q"),
                            opts,
                            answer_from_index(opts, q.get("answer")),
                            str(q.get("explanation") or ""),
                        )
                    )
                skill = str(block.get("type") or block.get("section") or path.stem).lower()
                uid = safe_id(f"ky_{year_dir.name}_{path.stem}")
                if "writ" in skill or "作文" in title:
                    out["writing"].append(
                        {
                            "id": uid,
                            "type": "writing",
                            "prompt": (passage or title)[:4000],
                            "rubric": "generic",
                            "min_words": 160,
                        }
                    )
                elif "listen" in skill:
                    out["listening"].append(
                        {
                            "id": uid,
                            "type": "listening",
                            "title": title,
                            "script": passage[:8000],
                            "audio_url": "",
                            "questions": qs,
                        }
                    )
                else:
                    if qs:
                        out["reading"].append(
                            {
                                "id": uid,
                                "type": "reading",
                                "title": title,
                                "passage": passage[:12000] or title,
                                "questions": qs,
                            }
                        )
                        out["vocab"].extend(qs[:3])
    print(f"structured-kaoyan: R{len(out['reading'])} V{len(out['vocab'])} W{len(out['writing'])}")
    return out


# ---------- Write packs ----------


def write_pack(family: str, sections: dict[str, list], sources: list[str]) -> Path:
    meta = META[family]
    # Cap extremely large packs to keep git/API sane while still "full"
    caps = {
        "vocab": 800,
        "listening": 400,
        "reading": 400,
        "writing": 200,
        "speaking": 200,
    }
    trimmed = {}
    for skill, items in sections.items():
        trimmed[skill] = items[: caps.get(skill, 400)]
    pack = {
        "family_id": family,
        "title": meta["title"],
        "cefr": meta["cefr"],
        "version": 2,
        "sources": sources,
        "counts": {k: len(v) for k, v in trimmed.items()},
        "sections": trimmed,
        "mock": meta["mock"],
    }
    PACKS.mkdir(parents=True, exist_ok=True)
    path = PACKS / f"pack_{family}.json"
    path.write_text(json.dumps(pack, ensure_ascii=False, indent=2), encoding="utf-8")
    size_mb = path.stat().st_size / (1024 * 1024)
    print(f"wrote {path.name} ({size_mb:.2f} MB) counts={pack['counts']}")
    if size_mb > 15:
        print(f"WARNING {path.name} > 15MB — consider split later")
    return path


def main() -> None:
    MEDIA_OUT.mkdir(parents=True, exist_ok=True)
    packs: dict[str, dict[str, list]] = {fam: load_base_pack(fam) for fam in META}
    sources: dict[str, list[str]] = defaultdict(list)

    esq_dir = VENDOR / "esq-releases"
    cet4_esq = esq_dir / "cet4-complete-v1.2.1.esq"
    cet6_esq = esq_dir / "cet6-complete-v1.2.1.esq"
    ky1 = esq_dir / "postgraduate-english-one-2002-2010-2026-v1.1.3.esq"
    ky2 = esq_dir / "postgraduate-english-two-2010-2025-v1.1.3.esq"

    # Extract audio for all papers (large but required by plan)
    if cet4_esq.exists():
        merge_sections(packs["cet4"], convert_esq(cet4_esq, "cet4", extract_audio=True))
        sources["cet4"].append("wssfk12138/english-question-banks cet4 ESQ")
    if cet6_esq.exists():
        merge_sections(packs["cet6"], convert_esq(cet6_esq, "cet6", extract_audio=True))
        sources["cet6"].append("wssfk12138/english-question-banks cet6 ESQ")
    for ky in (ky1, ky2):
        if ky.exists():
            merge_sections(packs["kaoyan"], convert_esq(ky, "kaoyan", extract_audio=False))
            sources["kaoyan"].append(ky.name)

    gong = VENDOR / "cet4-gongyining"
    if gong.exists():
        merge_sections(packs["cet4"], convert_gongyining(gong))
        sources["cet4"].append("gongyining0601/cet4")

    flu = VENDOR / "fluova"
    if flu.exists():
        merge_sections(packs["toefl"], convert_fluova(flu))
        sources["toefl"].append("emrecpn/fluova")

    ptera = VENDOR / "pteracai" / "public" / "data" / "bank.json"
    if ptera.exists():
        merge_sections(packs["ielts_ac"], convert_pteracai(ptera, "ielts"))
        merge_sections(packs["toefl"], convert_pteracai(ptera, "toefl"))
        sources["ielts_ac"].append("fthrvi/pteracai")
        sources["toefl"].append("fthrvi/pteracai")

    tip = VENDOR / "toefl-ielts-prep"
    if tip.exists():
        ielts_s, toefl_s = convert_toefl_ielts_prep(tip)
        merge_sections(packs["ielts_ac"], ielts_s)
        merge_sections(packs["toefl"], toefl_s)
        sources["ielts_ac"].append("Looffeeuu/toefl-ielts-prep")
        sources["toefl"].append("Looffeeuu/toefl-ielts-prep")

    expr = VENDOR / "ExpressAI-Exams"
    if expr.exists():
        merge_sections(packs["gaokao"], convert_expressai(expr))
        sources["gaokao"].append("ExpressAI/Exams")

    gk2026 = VENDOR / "gaokao-2026-english-exam" / "gaokao-2026-english-exam.html"
    if not gk2026.exists():
        # nested
        hits = list((VENDOR / "gaokao-2026-english-exam").rglob("*.html")) if (VENDOR / "gaokao-2026-english-exam").exists() else []
        gk2026 = hits[0] if hits else gk2026
    if gk2026.exists():
        merge_sections(packs["gaokao"], convert_gaokao_2026_html(gk2026))
        sources["gaokao"].append("daligao/gaokao-2026-english-exam")

    smart = VENDOR / "SmartGaokaoPastPapers"
    if smart.exists():
        g, z, k = convert_smart_gaokao(smart)
        merge_sections(packs["gaokao"], g)
        merge_sections(packs["zhongkao"], z)
        merge_sections(packs["k12_general"], k)
        sources["gaokao"].append("guorentao/SmartGaokaoPastPapers")
        sources["zhongkao"].append("guorentao/SmartGaokaoPastPapers")
        sources["k12_general"].append("guorentao/SmartGaokaoPastPapers")

    ielts_ai = VENDOR / "ielts-ai-dataset"
    if ielts_ai.exists():
        merge_sections(packs["ielts_ac"], convert_ielts_ai(ielts_ai))
        sources["ielts_ac"].append("LuchoBazz/ielts-ai-dataset")

    ky_struct = VENDOR / "structured-kaoyan-english"
    if ky_struct.exists():
        merge_sections(packs["kaoyan"], convert_structured_kaoyan(ky_struct))
        sources["kaoyan"].append("LIziak112/structured-kaoyan-english")

    # KET: seed from k12/toefl easy reading + existing thin; copy light reading from zhongkao/k12
    merge_sections(packs["ket"], {k: list(v[:40]) for k, v in packs["k12_general"].items()})
    sources["ket"].append("derived-from-k12 + base thin pack")

    # If zhongkao still thin, mirror gaokao easier reading slice
    if len(packs["zhongkao"]["reading"]) < 5:
        merge_sections(
            packs["zhongkao"],
            {
                "reading": packs["gaokao"]["reading"][:30],
                "vocab": packs["gaokao"]["vocab"][:50],
                "writing": packs["gaokao"]["writing"][:10],
                "listening": packs["gaokao"]["listening"][:20],
                "speaking": [],
            },
        )
        sources["zhongkao"].append("mirrored-gaokao-slice")
    if len(packs["k12_general"]["reading"]) < 5:
        merge_sections(
            packs["k12_general"],
            {
                "reading": packs["zhongkao"]["reading"][:20] or packs["gaokao"]["reading"][:20],
                "vocab": packs["zhongkao"]["vocab"][:40] or packs["gaokao"]["vocab"][:40],
                "writing": packs["zhongkao"]["writing"][:8] or packs["gaokao"]["writing"][:8],
                "listening": [],
                "speaking": [],
            },
        )
        sources["k12_general"].append("mirrored-zhongkao/gaokao-slice")

    for fam in META:
        write_pack(fam, packs[fam], sources.get(fam) or ["base-thin"])


if __name__ == "__main__":
    main()
