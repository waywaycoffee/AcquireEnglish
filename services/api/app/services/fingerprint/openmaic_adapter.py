"""OpenMAIC orchestration adapter for textbook → lesson packs.

OpenMAIC (THU-MAIC/OpenMAIC) is not vendored here. This module talks to a
configured HTTP endpoint and never hard-fails private uploads: callers use
`decompose_and_annotate`, which falls back to HeuristicSplitter on any error.

Supported remote modes (auto-detected):

1. **AcquireEnglish decompose contract** (preferred for textbook P1)::

       POST {OPENMAIC_URL}/api/v1/decompose
       {"cleaned_text": "...", "asset_name": "...", "constraints": {...}}
       → {"lessons": [{lesson_no, title, text_content, goal?, target_words?,
                       oral_outline?, cefr?}]}

2. **Native OpenMAIC classroom API** (when `/api/generate-classroom/capabilities`
   answers)::

       POST /api/materials  (text/plain body)
       POST /api/generate-classroom
       GET  pollUrl until succeeded
       map scenes / outline → lessons (slice source text by titles)

Local stand-in: ``tools/openmaic_mock`` implements (1) and optional LLM enrichment.
"""

from __future__ import annotations

import json
import logging
import re
import time
import urllib.error
import urllib.parse
import urllib.request
from typing import Any, Protocol
from urllib.parse import quote

from app.services.fingerprint.annotate import annotate_lessons, clean_material_text

logger = logging.getLogger(__name__)

_DEFAULT_TIMEOUT = 45.0
_POLL_CAP_SEC = 180.0


class LessonSplitter(Protocol):
    def split(
        self,
        cleaned_text: str,
        *,
        asset_name: str = "",
    ) -> list[dict[str, Any]]:
        ...


class HeuristicSplitter:
    """Chapter/length heuristic — default when OpenMAIC is off or unreachable."""

    def split(
        self,
        cleaned_text: str,
        *,
        asset_name: str = "",
    ) -> list[dict[str, Any]]:
        from app.services.fingerprint.service import decompose_text_to_lessons

        return decompose_text_to_lessons(
            cleaned_text,
            asset_name=asset_name,
            annotate=False,
        )


def _json_request(
    method: str,
    url: str,
    *,
    body: bytes | None = None,
    headers: dict[str, str] | None = None,
    timeout: float = _DEFAULT_TIMEOUT,
) -> tuple[int, Any, dict[str, str]]:
    req_headers = dict(headers or {})
    req = urllib.request.Request(url, data=body, headers=req_headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            raw = resp.read()
            ctype = (resp.headers.get("Content-Type") or "").lower()
            parsed: Any
            if "json" in ctype or (raw[:1] in (b"{", b"[")):
                try:
                    parsed = json.loads(raw.decode("utf-8", errors="replace"))
                except json.JSONDecodeError:
                    parsed = raw.decode("utf-8", errors="replace")
            else:
                parsed = raw.decode("utf-8", errors="replace")
            out_headers = {k.lower(): v for k, v in resp.headers.items()}
            # Preserve Set-Cookie for owner jar (urllib doesn't auto-jar).
            set_cookie = resp.headers.get("Set-Cookie")
            if set_cookie:
                out_headers["set-cookie"] = set_cookie
            return int(resp.status), parsed, out_headers
    except urllib.error.HTTPError as exc:
        raw = exc.read() if exc.fp else b""
        try:
            parsed = json.loads(raw.decode("utf-8", errors="replace"))
        except Exception:  # noqa: BLE001
            parsed = raw.decode("utf-8", errors="replace")
        return int(exc.code), parsed, {}


def _cookie_from_set_cookie(set_cookie: str | None, existing: str = "") -> str:
    if not set_cookie:
        return existing
    # Take first name=value from each Set-Cookie; merge into jar string.
    jar: dict[str, str] = {}
    for part in (existing or "").split(";"):
        part = part.strip()
        if "=" in part:
            k, v = part.split("=", 1)
            jar[k.strip()] = v.strip()
    # urllib may join multiple Set-Cookie with comma; take first segment of each.
    first = set_cookie.split(",")[0]
    pair = first.split(";")[0].strip()
    if "=" in pair:
        k, v = pair.split("=", 1)
        jar[k.strip()] = v.strip()
    return "; ".join(f"{k}={v}" for k, v in jar.items())


def _normalize_lesson(raw: dict[str, Any], index: int, source_text: str) -> dict[str, Any]:
    title = str(raw.get("title") or raw.get("name") or f"Lesson {index}")[:256]
    text = str(
        raw.get("text_content")
        or raw.get("plain_text")
        or raw.get("text")
        or raw.get("content")
        or ""
    ).strip()
    if not text and source_text:
        # Title-only outline item: leave empty for later slice fill.
        text = ""
    out: dict[str, Any] = {
        "lesson_no": int(raw.get("lesson_no") or index),
        "title": title,
        "text_content": text,
    }
    if raw.get("goal"):
        out["goal"] = str(raw["goal"])[:500]
    if raw.get("cefr"):
        out["cefr"] = str(raw["cefr"])[:8]
    tw = raw.get("target_words")
    if isinstance(tw, list) and tw:
        words: list[dict[str, Any]] = []
        for item in tw:
            if isinstance(item, str) and item.strip():
                words.append({"word": item.strip().lower()})
            elif isinstance(item, dict) and item.get("word"):
                words.append(
                    {
                        "word": str(item["word"]).strip().lower(),
                        **(
                            {"rank": int(item["rank"])}
                            if item.get("rank") is not None
                            else {}
                        ),
                        **(
                            {"cefr": str(item["cefr"])}
                            if item.get("cefr")
                            else {}
                        ),
                    }
                )
        if words:
            out["target_words"] = words[:8]
    oral = raw.get("oral_outline") or raw.get("oral") or raw.get("speaking_outline")
    if oral:
        if isinstance(oral, list):
            out["oral_outline"] = [str(x)[:240] for x in oral[:12]]
        else:
            out["oral_outline"] = [str(oral)[:240]]
    shadow = raw.get("shadow_lines") or raw.get("shadow")
    if isinstance(shadow, list) and shadow:
        out["shadow_lines"] = [str(x)[:240] for x in shadow[:16]]
    return out


def _slice_source_by_titles(
    source: str, lessons: list[dict[str, Any]]
) -> list[dict[str, Any]]:
    """Fill empty text_content by locating successive titles in source text."""
    if not source or not lessons:
        return lessons
    lower = source.lower()
    spans: list[tuple[int, int]] = []
    search_from = 0
    for L in lessons:
        title = str(L.get("title") or "").strip()
        if not title or L.get("text_content"):
            spans.append((-1, -1))
            continue
        # Try full title, then first meaningful token sequence.
        idx = lower.find(title.lower(), search_from)
        if idx < 0:
            key = re.sub(r"^(lesson|unit|chapter|part)\s*\d+[:.\s-]*", "", title, flags=re.I).strip()
            idx = lower.find(key.lower(), search_from) if key and len(key) >= 4 else -1
        spans.append((idx, -1))
        if idx >= 0:
            search_from = idx + max(1, len(title) // 2)

    starts = [s for s, _ in spans]
    out: list[dict[str, Any]] = []
    for i, L in enumerate(lessons):
        item = dict(L)
        if item.get("text_content"):
            out.append(item)
            continue
        start = starts[i]
        if start < 0:
            # Even split fallback for this lesson later.
            out.append(item)
            continue
        end = len(source)
        for j in range(i + 1, len(starts)):
            if starts[j] > start:
                end = starts[j]
                break
        body = source[start:end].strip()
        # Drop the title line itself when present at head.
        lines = body.splitlines()
        if lines and title_like_match(lines[0], str(item.get("title") or "")):
            body = "\n".join(lines[1:]).strip()
        item["text_content"] = body
        out.append(item)

    # Any still-empty: distribute remaining paragraphs round-robin.
    empties = [i for i, L in enumerate(out) if not str(L.get("text_content") or "").strip()]
    if empties:
        paras = [p.strip() for p in re.split(r"\n\s*\n", source) if p.strip()]
        if paras:
            for n, i in enumerate(empties):
                chunk = paras[n :: max(1, len(empties))]
                out[i]["text_content"] = "\n\n".join(chunk) if chunk else source[:800]
    return out


def title_like_match(line: str, title: str) -> bool:
    a = re.sub(r"\s+", " ", (line or "").strip().lower())
    b = re.sub(r"\s+", " ", (title or "").strip().lower())
    return bool(a and b and (a == b or a.startswith(b) or b.startswith(a)))


def map_openmaic_payload_to_lessons(
    payload: Any,
    *,
    source_text: str = "",
    asset_name: str = "",
) -> list[dict[str, Any]]:
    """Normalize decompose / classroom / outline JSON into lesson dicts."""
    lessons_raw: list[Any] = []
    if isinstance(payload, list):
        lessons_raw = payload
    elif isinstance(payload, dict):
        for key in ("lessons", "units", "chapters", "outline", "outlines", "scenes"):
            val = payload.get(key)
            if isinstance(val, list) and val:
                lessons_raw = val
                break
        if not lessons_raw:
            result = payload.get("result") if isinstance(payload.get("result"), dict) else {}
            for key in ("lessons", "scenes", "outline", "outlines"):
                val = (result or {}).get(key)
                if isinstance(val, list) and val:
                    lessons_raw = val
                    break
            classroom = result.get("classroom") if isinstance(result, dict) else None
            if not lessons_raw and isinstance(classroom, dict):
                scenes = classroom.get("scenes") or classroom.get("outline")
                if isinstance(scenes, list):
                    lessons_raw = scenes
            if not lessons_raw and isinstance(payload.get("classroom"), dict):
                scenes = payload["classroom"].get("scenes")
                if isinstance(scenes, list):
                    lessons_raw = scenes

    if not lessons_raw:
        return []

    # Group consecutive OpenMAIC scenes into lesson-sized packs when many slides.
    normalized: list[dict[str, Any]] = []
    for i, raw in enumerate(lessons_raw, start=1):
        if not isinstance(raw, dict):
            continue
        # Scene content may nest text.
        if not raw.get("text_content") and isinstance(raw.get("content"), dict):
            content = raw["content"]
            # Prefer narration / speech actions.
            bits: list[str] = []
            for act in raw.get("actions") or []:
                if isinstance(act, dict) and act.get("type") in ("speech", "narration"):
                    t = act.get("text") or act.get("content") or ""
                    if t:
                        bits.append(str(t))
            if bits:
                raw = {**raw, "text_content": "\n".join(bits)}
            elif content.get("type") == "quiz":
                qs = content.get("questions") or []
                raw = {
                    **raw,
                    "text_content": "\n".join(
                        str(q.get("question") or "") for q in qs if isinstance(q, dict)
                    ),
                }
        item = _normalize_lesson(raw, i, source_text)
        if item["title"] or item["text_content"]:
            normalized.append(item)

    if not normalized:
        return []

    normalized = _slice_source_by_titles(source_text, normalized)
    # Drop empty leftovers; ensure lesson_no sequence.
    kept = [L for L in normalized if str(L.get("text_content") or "").strip()]
    if not kept and source_text.strip():
        # Last resort: single lesson from source.
        kept = [
            {
                "lesson_no": 1,
                "title": (asset_name or "Lesson 1")[:256],
                "text_content": source_text.strip(),
            }
        ]
    for i, L in enumerate(kept, start=1):
        L["lesson_no"] = i
    return kept


class OpenMaicSplitter:
    """HTTP client for OpenMAIC / AcquireEnglish decompose endpoints."""

    def __init__(
        self,
        base_url: str | None = None,
        *,
        timeout: float | None = None,
        access_code: str | None = None,
        bearer_token: str | None = None,
        poll_timeout_sec: float | None = None,
    ) -> None:
        self.base_url = (base_url or "").rstrip("/")
        self.timeout = float(timeout if timeout is not None else _DEFAULT_TIMEOUT)
        self.access_code = (access_code or "").strip()
        self.bearer_token = (bearer_token or "").strip()
        self.poll_timeout_sec = float(
            poll_timeout_sec if poll_timeout_sec is not None else _POLL_CAP_SEC
        )
        self._cookie = ""
        self._mode: str | None = None  # "decompose" | "native" | None

    def _auth_headers(self, extra: dict[str, str] | None = None) -> dict[str, str]:
        h = dict(extra or {})
        if self.bearer_token:
            h.setdefault("Authorization", f"Bearer {self.bearer_token}")
        if self._cookie:
            h["Cookie"] = self._cookie
        return h

    def _remember_cookies(self, headers: dict[str, str]) -> None:
        sc = headers.get("set-cookie")
        if sc:
            self._cookie = _cookie_from_set_cookie(sc, self._cookie)

    def _ensure_access(self) -> None:
        if not self.access_code or self._cookie:
            return
        url = f"{self.base_url}/api/access-code/verify"
        body = json.dumps({"code": self.access_code}).encode("utf-8")
        status, _payload, hdrs = _json_request(
            "POST",
            url,
            body=body,
            headers=self._auth_headers({"Content-Type": "application/json"}),
            timeout=min(15.0, self.timeout),
        )
        self._remember_cookies(hdrs)
        if status >= 400:
            logger.warning("OpenMAIC access-code verify failed status=%s", status)

    def detect_mode(self) -> str:
        if self._mode:
            return self._mode
        self._ensure_access()
        # Prefer lightweight decompose contract.
        status, payload, hdrs = _json_request(
            "GET",
            f"{self.base_url}/api/v1/decompose",
            headers=self._auth_headers(),
            timeout=min(8.0, self.timeout),
        )
        self._remember_cookies(hdrs)
        if status in (200, 405) or (
            status == 404 and isinstance(payload, dict) and payload.get("service")
        ):
            # 405 = method not allowed on GET but route exists; mock returns 200 docs.
            if status != 404:
                self._mode = "decompose"
                return self._mode

        status2, payload2, hdrs2 = _json_request(
            "GET",
            f"{self.base_url}/api/generate-classroom/capabilities",
            headers=self._auth_headers(),
            timeout=min(8.0, self.timeout),
        )
        self._remember_cookies(hdrs2)
        if status2 == 200 and (
            isinstance(payload2, dict)
            and (payload2.get("success") is True or "capabilities" in payload2)
        ):
            self._mode = "native"
            return self._mode

        # Health-only: still try decompose POST first at call time.
        status3, _, hdrs3 = _json_request(
            "GET",
            f"{self.base_url}/api/health",
            headers=self._auth_headers(),
            timeout=min(5.0, self.timeout),
        )
        self._remember_cookies(hdrs3)
        if status3 == 200:
            self._mode = "decompose"
            return self._mode

        self._mode = "decompose"
        return self._mode

    def split(
        self,
        cleaned_text: str,
        *,
        asset_name: str = "",
    ) -> list[dict[str, Any]]:
        if not self.base_url:
            raise RuntimeError(
                "OpenMAIC base URL not configured; use HeuristicSplitter"
            )
        text = (cleaned_text or "").strip()
        if not text:
            return []
        self._ensure_access()
        mode = self.detect_mode()
        if mode == "native":
            try:
                return self._split_native(text, asset_name=asset_name)
            except Exception as exc:  # noqa: BLE001
                logger.warning(
                    "Native OpenMAIC failed (%s); trying /api/v1/decompose", exc
                )
        return self._split_decompose(text, asset_name=asset_name)

    def _split_decompose(
        self, cleaned_text: str, *, asset_name: str
    ) -> list[dict[str, Any]]:
        url = f"{self.base_url}/api/v1/decompose"
        body = json.dumps(
            {
                "cleaned_text": cleaned_text,
                "asset_name": asset_name or "",
                "constraints": {
                    "min_lesson_chars": 160,
                    "max_lesson_chars": 2800,
                    "target_words_min": 3,
                    "target_words_max": 8,
                    "include_oral_outline": True,
                    "include_shadow": True,
                },
            },
            ensure_ascii=False,
        ).encode("utf-8")
        status, payload, hdrs = _json_request(
            "POST",
            url,
            body=body,
            headers=self._auth_headers({"Content-Type": "application/json"}),
            timeout=self.timeout,
        )
        self._remember_cookies(hdrs)
        if status >= 400:
            raise RuntimeError(f"OpenMAIC decompose HTTP {status}: {payload!r}"[:400])
        lessons = map_openmaic_payload_to_lessons(
            payload, source_text=cleaned_text, asset_name=asset_name
        )
        if not lessons:
            raise RuntimeError("OpenMAIC decompose returned no lessons")
        return lessons

    def _split_native(
        self, cleaned_text: str, *, asset_name: str
    ) -> list[dict[str, Any]]:
        """THU-MAIC OpenMAIC: upload material → generate-classroom → map scenes."""
        fname = quote((asset_name or "textbook.txt").replace("/", "_")[:80] or "textbook.txt")
        if not fname.lower().endswith(".txt"):
            fname = f"{fname}.txt"
        material_body = cleaned_text.encode("utf-8")
        status, mat, hdrs = _json_request(
            "POST",
            f"{self.base_url}/api/materials",
            body=material_body,
            headers=self._auth_headers(
                {
                    "Content-Type": "text/plain; charset=utf-8",
                    "X-Material-Filename": fname,
                }
            ),
            timeout=self.timeout,
        )
        self._remember_cookies(hdrs)
        if status not in (200, 201) or not isinstance(mat, dict):
            raise RuntimeError(f"OpenMAIC materials upload failed: HTTP {status}")
        material_id = str(mat.get("materialId") or mat.get("id") or "").strip()
        if not material_id:
            raise RuntimeError("OpenMAIC materials response missing materialId")

        requirement = (
            "Decompose this English learning textbook into a multi-lesson curriculum "
            "for adult English learners. Each lesson should cover a coherent reading "
            "passage with a clear learning goal, key vocabulary, and a short oral "
            "practice outline. Prefer reading-focused scenes over quizzes."
        )
        if asset_name:
            requirement = f"{requirement} Course title hint: {asset_name}."

        status, job, hdrs = _json_request(
            "POST",
            f"{self.base_url}/api/generate-classroom",
            body=json.dumps(
                {"requirement": requirement, "materialIds": [material_id]},
                ensure_ascii=False,
            ).encode("utf-8"),
            headers=self._auth_headers({"Content-Type": "application/json"}),
            timeout=self.timeout,
        )
        self._remember_cookies(hdrs)
        if status >= 400 or not isinstance(job, dict):
            raise RuntimeError(f"OpenMAIC generate-classroom failed: HTTP {status} {job!r}"[:400])

        poll_url = str(job.get("pollUrl") or "").strip()
        job_id = str(job.get("jobId") or job.get("runId") or "").strip()
        if not poll_url:
            if not job_id:
                raise RuntimeError("OpenMAIC job missing pollUrl/jobId")
            poll_url = f"{self.base_url}/api/generate-classroom/{job_id}"
        interval = float(job.get("pollIntervalMs") or 5000) / 1000.0
        interval = max(3.0, min(interval, 30.0))

        deadline = time.monotonic() + self.poll_timeout_sec
        final: dict[str, Any] | None = None
        while time.monotonic() < deadline:
            time.sleep(interval)
            st, poll, hdrs = _json_request(
                "GET",
                poll_url,
                headers=self._auth_headers(),
                timeout=self.timeout,
            )
            self._remember_cookies(hdrs)
            if st == 404:
                raise RuntimeError(f"OpenMAIC job not found: {job_id}")
            if st >= 500:
                continue
            if not isinstance(poll, dict):
                continue
            status_s = str(poll.get("status") or "").lower()
            if status_s in ("succeeded", "success", "done", "completed"):
                final = poll
                break
            if status_s in ("failed", "error"):
                raise RuntimeError(
                    f"OpenMAIC generation failed: {poll.get('error') or poll}"[:400]
                )
        if final is None:
            raise RuntimeError(
                f"OpenMAIC generation timed out after {self.poll_timeout_sec:.0f}s"
            )

        # Enrich from generation-runs when classroom body is thin.
        run_id = str(final.get("runId") or job_id or "").strip()
        if run_id:
            st, run_body, hdrs = _json_request(
                "GET",
                f"{self.base_url}/api/generation-runs/{run_id}",
                headers=self._auth_headers(),
                timeout=self.timeout,
            )
            self._remember_cookies(hdrs)
            if st == 200 and isinstance(run_body, dict):
                final = {**final, "generation_run": run_body}

        lessons = map_openmaic_payload_to_lessons(
            final, source_text=cleaned_text, asset_name=asset_name
        )
        # Best-effort cleanup of uploaded material.
        try:
            _json_request(
                "DELETE",
                f"{self.base_url}/api/materials/{material_id}",
                headers=self._auth_headers(),
                timeout=min(10.0, self.timeout),
            )
        except Exception:  # noqa: BLE001
            pass
        if not lessons:
            raise RuntimeError("OpenMAIC native response mapped to zero lessons")
        return lessons


def get_splitter(
    *,
    prefer_openmaic: bool | None = None,
    openmaic_url: str | None = None,
) -> LessonSplitter:
    """Return OpenMAIC client when URL configured (and preferred), else heuristic."""
    url = openmaic_url
    prefer = prefer_openmaic
    if url is None or prefer is None:
        try:
            from app.config import settings

            if url is None:
                url = getattr(settings, "openmaic_url", "") or ""
            if prefer is None:
                prefer = bool(getattr(settings, "prefer_openmaic", True))
        except Exception:  # noqa: BLE001
            url = url or ""
            prefer = True if prefer is None else prefer

    url = (url or "").strip()
    if prefer and url:
        timeout = _DEFAULT_TIMEOUT
        access = ""
        bearer = ""
        poll = _POLL_CAP_SEC
        try:
            from app.config import settings

            timeout = float(getattr(settings, "openmaic_timeout_seconds", timeout) or timeout)
            access = str(getattr(settings, "openmaic_access_code", "") or "")
            bearer = str(getattr(settings, "openmaic_bearer_token", "") or "")
            poll = float(
                getattr(settings, "openmaic_poll_timeout_seconds", poll) or poll
            )
        except Exception:  # noqa: BLE001
            pass
        return OpenMaicSplitter(
            url,
            timeout=timeout,
            access_code=access,
            bearer_token=bearer,
            poll_timeout_sec=poll,
        )
    return HeuristicSplitter()


def decompose_and_annotate(
    raw_or_cleaned: str,
    *,
    asset_name: str = "",
    splitter: LessonSplitter | None = None,
    already_cleaned: bool = False,
) -> tuple[list[dict[str, Any]], str, dict[str, Any]]:
    """Split + annotate. OpenMAIC failures soft-fall back to heuristic (never raise)."""
    text = raw_or_cleaned if already_cleaned else clean_material_text(raw_or_cleaned)
    engine = splitter or get_splitter()
    lessons: list[dict[str, Any]] = []
    try:
        lessons = engine.split(text, asset_name=asset_name)
    except Exception as exc:  # noqa: BLE001
        if not isinstance(engine, HeuristicSplitter):
            logger.warning(
                "OpenMAIC split failed (%s); falling back to HeuristicSplitter", exc
            )
            lessons = HeuristicSplitter().split(text, asset_name=asset_name)
        else:
            raise
    if not lessons:
        lessons = HeuristicSplitter().split(text, asset_name=asset_name)
    return annotate_lessons(lessons)
