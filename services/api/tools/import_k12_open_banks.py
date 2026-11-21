"""Import cn-math-taxonomy English + RACE (+ CLOTH/SC-Ques when present) into ExamPacks.

Vendor caches live under data/exam_bank_vendor/ (gitignored).
RACE / CLOTH / SC-Ques / cn-math English are research or CC BY-NC — packs carry
license metadata; commercial redistribution needs separate rights.

Optional downloads (do not commit archives)::

  CLOTH:
    mkdir -p data/exam_bank_vendor/CLOTH
    # Research dump: https://www.qizhexie.com/data/CLOTH  (CLOTH.tar.gz)
    # Place CLOTH.tar.gz under CLOTH/ — converter auto-extracts to _extracted/

  SC-Ques:
    # https://github.com/ai4ed/SC-Ques — put dataset json/jsonl under
    # data/exam_bank_vendor/SC-Ques/datasets/  (repo code alone is not enough)

  Then:  python tools/import_k12_open_banks.py
"""

from __future__ import annotations

import json
import re
import tarfile
from collections import defaultdict
from pathlib import Path
from typing import Any

try:
    import pyarrow.parquet as pq
except ImportError:  # pragma: no cover
    pq = None  # type: ignore

ROOT = Path(__file__).resolve().parents[1]
VENDOR = ROOT / "data" / "exam_bank_vendor"
PACKS = ROOT / "data" / "exam_packs"

# Caps: dedicated research packs can be larger; merged family packs stay modest.
CAPS_FAMILY = {
    "vocab": 800,
    "listening": 400,
    "reading": 400,
    "writing": 200,
    "speaking": 200,
}
CAPS_DEDICATED = {
    "vocab": 2000,
    "listening": 200,
    "reading": 2000,  # keep pack JSON under ~15MB for git
    "writing": 100,
    "speaking": 100,
}


def empty_sections() -> dict[str, list]:
    return {
        "vocab": [],
        "listening": [],
        "reading": [],
        "writing": [],
        "speaking": [],
    }


def safe_id(raw: str) -> str:
    s = re.sub(r"[^a-zA-Z0-9_\-.]+", "_", str(raw)).strip("._")
    return s[:120] or "item"


def mcq(pid: str, prompt: str, options: list[str], answer: str, explain: str = "") -> dict:
    return {
        "id": pid,
        "type": "mcq",
        "prompt": prompt,
        "options": options,
        "answer": answer,
        "explain": explain or "",
    }


def answer_letter_to_text(options: list[str], letter: Any) -> str:
    if isinstance(letter, str) and letter.strip().upper() in "ABCDEFGH":
        i = ord(letter.strip().upper()) - ord("A")
        if 0 <= i < len(options):
            return options[i]
    try:
        i = int(letter)
        if 0 <= i < len(options):
            return options[i]
    except (TypeError, ValueError):
        pass
    return str(letter)


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


def load_pack_sections(family: str) -> dict[str, list]:
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


def write_pack(
    family: str,
    *,
    title: str,
    cefr: str,
    sections: dict[str, list],
    sources: list[str],
    license_id: str,
    commercial_ok: bool,
    mock: dict[str, Any],
    caps: dict[str, int] | None = None,
    extra: dict[str, Any] | None = None,
) -> Path:
    use_caps = caps or CAPS_FAMILY
    trimmed = {k: (v[: use_caps.get(k, 400)]) for k, v in sections.items()}
    pack: dict[str, Any] = {
        "family_id": family,
        "title": title,
        "cefr": cefr,
        "version": 3,
        "sources": sources,
        "license": license_id,
        "commercial_ok": commercial_ok,
        "counts": {k: len(v) for k, v in trimmed.items()},
        "sections": trimmed,
        "mock": mock,
    }
    if extra:
        pack.update(extra)
    PACKS.mkdir(parents=True, exist_ok=True)
    path = PACKS / f"pack_{family}.json"
    path.write_text(json.dumps(pack, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"wrote {path.name} ({path.stat().st_size / 1024 / 1024:.2f} MB) counts={pack['counts']}")
    return path


# ---------- cn-math-taxonomy English ----------


def convert_cn_math_english(root: Path) -> tuple[dict[str, dict[str, list]], dict[str, Any]]:
    """Return per-bucket sections + knowledge graph payload."""
    buckets = {
        "primary": empty_sections(),
        "junior": empty_sections(),
        "senior": empty_sections(),
        "all": empty_sections(),
    }
    qpath = root / "data" / "questions.json"
    tpath = root / "data" / "topics.json"
    dpath = root / "data" / "dependencies.json"
    if not qpath.is_file() or not tpath.is_file():
        print("skip cn-math-taxonomy (missing data)")
        return buckets, {}

    topics_raw = json.loads(tpath.read_text(encoding="utf-8"))
    eng_topics = {
        str(t["id"]): t
        for t in topics_raw
        if isinstance(t, dict) and str(t.get("subject") or "").lower() == "english"
    }
    questions = json.loads(qpath.read_text(encoding="utf-8"))
    eng_qs = [
        q
        for q in questions
        if isinstance(q, dict) and str(q.get("topicId") or "").startswith("cne_")
    ]

    for q in eng_qs:
        tid = str(q.get("topicId") or "")
        topic = eng_topics.get(tid) or {}
        grade = topic.get("grade")
        if tid.startswith("cne_p") or (isinstance(grade, int) and 3 <= grade <= 6):
            bucket = "primary"
        elif tid.startswith("cne_j") or (isinstance(grade, int) and 7 <= grade <= 9):
            bucket = "junior"
        else:
            bucket = "senior"

        prompt = str(q.get("prompt") or "").strip()
        explain = str(q.get("explanation") or "")
        qid = safe_id(q.get("id") or f"{tid}_{len(buckets[bucket]['vocab'])}")
        chapter = str(topic.get("chapter") or topic.get("name") or tid)
        knowledge = {
            "topic_id": tid,
            "topic_name": topic.get("name"),
            "grade": topic.get("grade"),
            "chapter": chapter,
            "domain": topic.get("domain"),
        }

        if q.get("type") == "choice" and isinstance(q.get("choices"), list):
            opts = []
            for c in q["choices"]:
                if isinstance(c, dict):
                    opts.append(str(c.get("text") or c.get("key") or ""))
                else:
                    opts.append(str(c))
            opts = [o for o in opts if o]
            if len(opts) < 2:
                continue
            ans = answer_letter_to_text(opts, q.get("answer"))
            item = mcq(qid, prompt or chapter, opts, ans, explain)
            item["knowledge"] = knowledge
            # Treat as vocab/grammar drills; also attach light reading wrapper when long
            buckets[bucket]["vocab"].append(item)
            buckets["all"]["vocab"].append(item)
            if len(prompt) > 180:
                buckets[bucket]["reading"].append(
                    {
                        "id": qid + "_r",
                        "type": "reading",
                        "title": chapter[:80],
                        "passage": prompt,
                        "questions": [mcq(qid + "_rq", "Choose the best answer.", opts, ans, explain)],
                        "knowledge": knowledge,
                    }
                )
                buckets["all"]["reading"].append(buckets[bucket]["reading"][-1])
        else:
            # numeric / short answer → writing-like prompt for practice
            buckets[bucket]["writing"].append(
                {
                    "id": qid,
                    "type": "writing",
                    "prompt": prompt or chapter,
                    "rubric": "k12_short",
                    "min_words": 1,
                    "answer_key": str(q.get("answer") or ""),
                    "explain": explain,
                    "knowledge": knowledge,
                }
            )
            buckets["all"]["writing"].append(buckets[bucket]["writing"][-1])

    deps_raw = []
    if dpath.is_file():
        try:
            deps_raw = json.loads(dpath.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            deps_raw = []
    eng_deps = [
        d
        for d in deps_raw
        if isinstance(d, dict)
        and str(d.get("topicId") or "").startswith("cne_")
        and str(d.get("prerequisiteId") or "").startswith("cne_")
    ]
    graph = {
        "id": "cn_english_taxonomy",
        "title": "人教 PEP / Go for it! / 高中必修 英语知识点图谱",
        "license": "CC-BY-NC-4.0",
        "commercial_ok": False,
        "source": "xiaoyang111222/cn-math-taxonomy",
        "topics": list(eng_topics.values()),
        "dependencies": eng_deps,
        "question_count": len(eng_qs),
    }
    print(
        "cn-math english:",
        f"Q{len(eng_qs)}",
        f"topics{len(eng_topics)}",
        f"deps{len(eng_deps)}",
        {k: len(v["vocab"]) for k, v in buckets.items() if k != "all"},
    )
    return buckets, graph


# ---------- RACE ----------


def _race_rows_from_parquet(path: Path) -> list[dict[str, Any]]:
    if pq is None:
        raise RuntimeError("pyarrow required to read RACE parquet (pip install pyarrow)")
    table = pq.read_table(path)
    cols = table.to_pydict()
    n = table.num_rows
    rows = []
    for i in range(n):
        rows.append({k: cols[k][i] for k in cols})
    return rows


def _race_rows_from_json_dir(root: Path) -> list[dict[str, Any]]:
    """Classic RACE layout: root/{train,dev,test}/{middle,high}/*.txt json."""
    rows: list[dict[str, Any]] = []
    for path in root.rglob("*.txt"):
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            continue
        if not isinstance(data, dict):
            continue
        article = str(data.get("article") or "")
        questions = data.get("questions") or []
        options = data.get("options") or []
        answers = data.get("answers") or []
        for i, q in enumerate(questions):
            opts = options[i] if i < len(options) else []
            ans = answers[i] if i < len(answers) else ""
            rows.append(
                {
                    "example_id": f"{path.stem}_{i}",
                    "article": article,
                    "question": q,
                    "options": opts,
                    "answer": ans,
                }
            )
    return rows


def convert_race(level: str, roots: list[Path], *, max_passages: int | None = None) -> dict[str, list]:
    """level: middle | high"""
    out = empty_sections()
    rows: list[dict[str, Any]] = []
    for root in roots:
        if not root.exists():
            continue
        # parquet (ModelScope)
        for split in ("train", "val", "test", "dev"):
            for p in root.rglob(f"{level}-*.parquet"):
                if split in str(p).replace("\\", "/"):
                    try:
                        rows.extend(_race_rows_from_parquet(p))
                    except Exception as e:
                        print("race parquet fail", p, e)
            for p in (root / "extracted" / "race" / split).glob(f"{level}-*.parquet"):
                try:
                    rows.extend(_race_rows_from_parquet(p))
                except Exception as e:
                    print("race parquet fail", p, e)
        # classic json txt
        for sub in root.rglob(level):
            if sub.is_dir():
                rows.extend(_race_rows_from_json_dir(sub))

    # Group by article to build reading items
    by_article: dict[str, dict[str, Any]] = {}
    for row in rows:
        article = str(row.get("article") or "").strip()
        if not article:
            continue
        key = article[:240]
        bucket = by_article.setdefault(
            key,
            {"passage": article, "questions": [], "ids": []},
        )
        opts = row.get("options") or []
        if isinstance(opts, list):
            opts = [str(o) for o in opts]
        else:
            continue
        if len(opts) < 2:
            continue
        qid = safe_id(row.get("example_id") or f"race_{level}_{len(bucket['questions'])}")
        ans = answer_letter_to_text(opts, row.get("answer"))
        bucket["questions"].append(
            mcq(qid, str(row.get("question") or "Q"), opts, ans)
        )
        bucket["ids"].append(qid)

    passages = list(by_article.values())
    if max_passages:
        passages = passages[:max_passages]
    for i, block in enumerate(passages):
        if not block["questions"]:
            continue
        rid = safe_id(f"race_{level}_{i}_{block['ids'][0]}")
        out["reading"].append(
            {
                "id": rid,
                "type": "reading",
                "title": f"RACE {level} #{i + 1}",
                "passage": block["passage"][:12000],
                "questions": block["questions"][:8],
                "source": "RACE",
                "license": "research-noncommercial",
            }
        )
        # also surface first question as vocab drill
        out["vocab"].extend(block["questions"][:1])
    print(f"RACE {level}: passages={len(out['reading'])} vocab={len(out['vocab'])} raw_rows={len(rows)}")
    return out


# ---------- CLOTH ----------


def convert_cloth(root: Path) -> tuple[dict[str, list], dict[str, list]]:
    """Return (middle, high) sections. CLOTH json: article with blanks + options + answers."""
    middle = empty_sections()
    high = empty_sections()
    if not root.exists():
        return middle, high

    files: list[Path] = []
    for p in root.rglob("*.json"):
        if p.name.startswith("_"):
            continue
        files.append(p)
    # also extract tar if only archive present
    for tar_path in list(root.glob("*.tar.gz")) + list(root.glob("*.tgz")):
        extract_dir = root / "_extracted"
        if not extract_dir.exists():
            try:
                with tarfile.open(tar_path, "r:gz") as tf:
                    tf.extractall(extract_dir)
            except (OSError, tarfile.TarError) as e:
                print("CLOTH tar fail", e)
                continue
        files.extend(extract_dir.rglob("*.json"))

    for path in files:
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            continue
        if not isinstance(data, dict):
            continue
        article = str(data.get("article") or data.get("passage") or "")
        options = data.get("options") or data.get("choices") or []
        answers = data.get("answers") or data.get("answer") or []
        if not article or not options:
            continue
        level = "high" if "high" in str(path).replace("\\", "/").lower() else "middle"
        if "middle" in str(path).replace("\\", "/").lower():
            level = "middle"
        target = high if level == "high" else middle
        qs = []
        for i, opts in enumerate(options):
            if not isinstance(opts, list) or len(opts) < 2:
                continue
            opts = [str(o) for o in opts]
            ans_raw = answers[i] if isinstance(answers, list) and i < len(answers) else ""
            ans = answer_letter_to_text(opts, ans_raw)
            qs.append(mcq(safe_id(f"cloth_{path.stem}_{i}"), f"Blank #{i + 1}", opts, ans))
        if not qs:
            continue
        rid = safe_id(f"cloth_{level}_{path.stem}")
        target["reading"].append(
            {
                "id": rid,
                "type": "reading",
                "title": f"CLOTH {level} {path.stem}",
                "passage": article[:12000],
                "questions": qs[:20],
                "source": "CLOTH",
                "license": "research-noncommercial",
            }
        )
        target["vocab"].extend(qs[:5])
    print(f"CLOTH middle R{len(middle['reading'])} high R{len(high['reading'])}")
    return middle, high


# ---------- SC-Ques ----------


def convert_scques(root: Path, *, max_items: int = 2000) -> dict[str, list]:
    out = empty_sections()
    if not root.exists():
        return out
    candidates: list[Path] = []
    for pat in ("**/*.json", "**/*.jsonl", "**/*.csv"):
        candidates.extend(root.glob(pat))
    count = 0
    for path in candidates:
        if path.stat().st_size > 200 * 1024 * 1024:
            continue
        try:
            if path.suffix == ".jsonl":
                lines = path.read_text(encoding="utf-8", errors="ignore").splitlines()
                rows = []
                for line in lines:
                    line = line.strip()
                    if not line:
                        continue
                    try:
                        rows.append(json.loads(line))
                    except json.JSONDecodeError:
                        continue
            elif path.suffix == ".csv":
                import csv

                with path.open(encoding="utf-8", errors="ignore") as f:
                    rows = list(csv.DictReader(f))
            else:
                data = json.loads(path.read_text(encoding="utf-8", errors="ignore"))
                if isinstance(data, list):
                    rows = data
                elif isinstance(data, dict):
                    rows = data.get("data") or data.get("questions") or data.get("items") or []
                else:
                    rows = []
        except (OSError, json.JSONDecodeError, UnicodeError):
            continue
        for row in rows:
            if not isinstance(row, dict):
                continue
            stem = str(
                row.get("question")
                or row.get("stem")
                or row.get("prompt")
                or row.get("sentence")
                or ""
            ).strip()
            if not stem:
                continue
            opts = row.get("options") or row.get("choices") or row.get("candidates") or []
            if isinstance(opts, dict):
                opts = [str(v) for _, v in sorted(opts.items())]
            else:
                opts = [str(o) for o in opts] if isinstance(opts, list) else []
            if len(opts) < 2:
                # sometimes label index into candidates elsewhere
                continue
            ans = answer_letter_to_text(
                opts, row.get("answer") or row.get("label") or row.get("correct")
            )
            qid = safe_id(row.get("id") or f"scq_{path.stem}_{count}")
            out["vocab"].append(mcq(qid, stem, opts, ans, str(row.get("explanation") or "")))
            count += 1
            if count >= max_items:
                print(f"SC-Ques: V{len(out['vocab'])} (capped)")
                return out
    print(f"SC-Ques: V{len(out['vocab'])}")
    return out


def _patch_existing_pack(family: str, add: dict[str, list], source: str, license_note: str) -> None:
    path = PACKS / f"pack_{family}.json"
    if not path.is_file():
        # create thin shell
        write_pack(
            family,
            title=family,
            cefr="A2",
            sections=add,
            sources=[source],
            license_id=license_note,
            commercial_ok=False,
            mock={"duration_minutes": 60, "sections": ["vocab", "reading"]},
        )
        return
    data = json.loads(path.read_text(encoding="utf-8"))
    sections = empty_sections()
    raw = data.get("sections") or {}
    for k in sections:
        sections[k] = list(raw.get(k) or [])
    merge_sections(sections, add)
    caps = CAPS_FAMILY
    trimmed = {k: v[: caps.get(k, 400)] for k, v in sections.items()}
    sources = list(data.get("sources") or [])
    if source not in sources:
        sources.append(source)
    data["sections"] = trimmed
    data["counts"] = {k: len(v) for k, v in trimmed.items()}
    data["sources"] = sources
    data["version"] = int(data.get("version") or 1) + 1
    # Keep stricter commercial flag if any research source present
    if not data.get("commercial_ok", True) or license_note != "unknown":
        if "research" in license_note.lower() or "BY-NC" in license_note or "CC-BY-NC" in license_note:
            data["commercial_ok"] = False
            data["license"] = data.get("license") or license_note
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"patched {path.name} counts={data['counts']}")


def main() -> None:
    PACKS.mkdir(parents=True, exist_ok=True)

    # 1) cn-math English
    cn_root = VENDOR / "cn-math-taxonomy"
    cn_buckets, graph = convert_cn_math_english(cn_root)
    if graph:
        graph_path = PACKS / "graph_cn_english.json"
        graph_path.write_text(json.dumps(graph, ensure_ascii=False, indent=2), encoding="utf-8")
        print(f"wrote {graph_path.name} topics={len(graph.get('topics') or [])}")

    write_pack(
        "cn_english_taxonomy",
        title="K12 英语知识点题库（PEP / Go for it! / 高中必修）",
        cefr="A2",
        sections=cn_buckets["all"],
        sources=["xiaoyang111222/cn-math-taxonomy (English cne_*)"],
        license_id="CC-BY-NC-4.0",
        commercial_ok=False,
        mock={"duration_minutes": 45, "sections": ["vocab", "reading"]},
        caps=CAPS_DEDICATED,
        extra={"knowledge_graph": "graph_cn_english.json"},
    )
    _patch_existing_pack(
        "k12_general",
        cn_buckets["primary"],
        "cn-math-taxonomy English primary (CC-BY-NC)",
        "CC-BY-NC-4.0",
    )
    _patch_existing_pack(
        "zhongkao",
        cn_buckets["junior"],
        "cn-math-taxonomy English junior (CC-BY-NC)",
        "CC-BY-NC-4.0",
    )
    _patch_existing_pack(
        "gaokao",
        cn_buckets["senior"],
        "cn-math-taxonomy English senior (CC-BY-NC)",
        "CC-BY-NC-4.0",
    )

    # 2) RACE
    race_roots = [
        VENDOR / "RACE_ms",
        VENDOR / "RACE_ms" / "extracted",
        VENDOR / "RACE",
        VENDOR / "RACE_github",
    ]
    race_middle = convert_race("middle", race_roots)
    race_high = convert_race("high", race_roots)
    if race_middle["reading"]:
        write_pack(
            "race_middle",
            title="RACE 初中阅读理解（研究用途）",
            cefr="A2",
            sections=race_middle,
            sources=["Lai et al. EMNLP 2017 / modelscope/race"],
            license_id="research-noncommercial",
            commercial_ok=False,
            mock={"duration_minutes": 40, "sections": ["reading"]},
            caps=CAPS_DEDICATED,
            extra={"attribution": "RACE dataset — research use only; not for commercial redistribution."},
        )
        _patch_existing_pack(
            "zhongkao",
            {"reading": race_middle["reading"][:120], "vocab": race_middle["vocab"][:80],
             "listening": [], "writing": [], "speaking": []},
            "RACE middle (research-only)",
            "research-noncommercial",
        )
    if race_high["reading"]:
        write_pack(
            "race_high",
            title="RACE 高中阅读理解（研究用途）",
            cefr="B1",
            sections=race_high,
            sources=["Lai et al. EMNLP 2017 / modelscope/race"],
            license_id="research-noncommercial",
            commercial_ok=False,
            mock={"duration_minutes": 45, "sections": ["reading"]},
            caps=CAPS_DEDICATED,
            extra={"attribution": "RACE dataset — research use only; not for commercial redistribution."},
        )
        _patch_existing_pack(
            "gaokao",
            {"reading": race_high["reading"][:120], "vocab": race_high["vocab"][:80],
             "listening": [], "writing": [], "speaking": []},
            "RACE high (research-only)",
            "research-noncommercial",
        )

    # 3) CLOTH (optional)
    cloth_middle, cloth_high = convert_cloth(VENDOR / "CLOTH")
    if not cloth_middle["reading"] and not cloth_high["reading"]:
        cloth_middle, cloth_high = convert_cloth(VENDOR / "CLOTH_repo")
    if cloth_middle["reading"] or cloth_high["reading"]:
        write_pack(
            "cloth_cloze",
            title="CLOTH 初高中完形填空（研究用途）",
            cefr="B1",
            sections={
                "vocab": cloth_middle["vocab"] + cloth_high["vocab"],
                "listening": [],
                "reading": cloth_middle["reading"] + cloth_high["reading"],
                "writing": [],
                "speaking": [],
            },
            sources=["Xie et al. CLOTH / www.qizhexie.com"],
            license_id="research-noncommercial",
            commercial_ok=False,
            mock={"duration_minutes": 40, "sections": ["reading", "vocab"]},
            caps=CAPS_DEDICATED,
        )
        if cloth_middle["reading"]:
            _patch_existing_pack(
                "zhongkao",
                {"reading": cloth_middle["reading"][:80], "vocab": cloth_middle["vocab"][:100],
                 "listening": [], "writing": [], "speaking": []},
                "CLOTH middle (research-only)",
                "research-noncommercial",
            )
        if cloth_high["reading"]:
            _patch_existing_pack(
                "gaokao",
                {"reading": cloth_high["reading"][:80], "vocab": cloth_high["vocab"][:100],
                 "listening": [], "writing": [], "speaking": []},
                "CLOTH high (research-only)",
                "research-noncommercial",
            )
    else:
        print("CLOTH data not present — converter ready; fetch CLOTH.tar.gz into exam_bank_vendor/CLOTH/")

    # 4) SC-Ques (optional)
    scq = convert_scques(VENDOR / "SC-Ques")
    if not scq["vocab"]:
        scq = convert_scques(VENDOR / "SC-Ques" / "datasets")
    if scq["vocab"]:
        write_pack(
            "scques_grammar",
            title="SC-Ques ESL 句子填空 / 语法单选",
            cefr="A2",
            sections=scq,
            sources=["ai4ed/SC-Ques"],
            license_id="research-check-paper",
            commercial_ok=False,
            mock={"duration_minutes": 30, "sections": ["vocab"]},
            caps=CAPS_DEDICATED,
        )
        _patch_existing_pack(
            "k12_general",
            {"vocab": scq["vocab"][:200], "listening": [], "reading": [], "writing": [], "speaking": []},
            "SC-Ques (check license)",
            "research-check-paper",
        )
    else:
        print("SC-Ques dataset archive not present — place SC-Ques.tar.gz under exam_bank_vendor/SC-Ques/datasets/")


if __name__ == "__main__":
    main()
