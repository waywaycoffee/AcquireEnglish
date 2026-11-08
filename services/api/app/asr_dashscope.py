"""Aliyun DashScope file transcription → SRT (mirrors mobile qwen3-asr flow)."""

from __future__ import annotations

import asyncio
import json
from pathlib import Path

import httpx

DEFAULT_MODEL = "qwen3-asr-flash-filetrans"
BASE_URL = "https://dashscope.aliyuncs.com"


def _fmt_ts(seconds: float) -> str:
    total_ms = max(0, int(round(seconds * 1000)))
    h, rem = divmod(total_ms, 3600_000)
    m, rem = divmod(rem, 60_000)
    s, ms = divmod(rem, 1000)
    return f"{h:02d}:{m:02d}:{s:02d},{ms:03d}"


def cues_to_srt(cues: list[tuple[float, float, str]]) -> str:
    lines: list[str] = []
    for i, (start, end, text) in enumerate(cues, start=1):
        content = " ".join(text.split()).strip()
        if not content:
            continue
        if end <= start:
            end = start + 0.8
        lines.append(str(i))
        lines.append(f"{_fmt_ts(start)} --> {_fmt_ts(end)}")
        lines.append(content)
        lines.append("")
    if not lines:
        raise ValueError("ASR 未识别到有效字幕")
    return "\n".join(lines)


def _ms_to_sec(value: object) -> float:
    if isinstance(value, (int, float)):
        # DashScope word timestamps are usually milliseconds.
        return float(value) / 1000.0 if value > 1000 else float(value)
    return 0.0


def _normalize_result(payload: object) -> list[tuple[float, float, str]]:
    """Best-effort parse of DashScope ASR JSON into sentence cues."""
    data = payload
    if isinstance(payload, str):
        data = json.loads(payload)
    if not isinstance(data, dict):
        raise ValueError("ASR 结果格式无效")

    transcripts = data.get("transcripts") or data.get("results") or []
    if not transcripts and "output" in data:
        output = data.get("output") or {}
        if isinstance(output, dict):
            transcripts = output.get("transcripts") or []

    cues: list[tuple[float, float, str]] = []

    # Prefer sentence-level entries when present.
    for block in transcripts if isinstance(transcripts, list) else []:
        if not isinstance(block, dict):
            continue
        sentences = block.get("sentences") or block.get("sentence_info") or []
        if isinstance(sentences, list) and sentences:
            for sent in sentences:
                if not isinstance(sent, dict):
                    continue
                text = str(sent.get("text") or sent.get("sentence") or "").strip()
                if not text:
                    continue
                start = _ms_to_sec(sent.get("begin_time", sent.get("start_time", sent.get("start", 0))))
                end = _ms_to_sec(sent.get("end_time", sent.get("end", start + 1)))
                cues.append((start, end, text))
            continue

        words = block.get("words") or block.get("tokens") or []
        if isinstance(words, list) and words:
            buf: list[str] = []
            start: float | None = None
            last_end = 0.0
            for word in words:
                if not isinstance(word, dict):
                    continue
                token = str(word.get("text") or word.get("word") or "").strip()
                if not token:
                    continue
                w_start = _ms_to_sec(word.get("begin_time", word.get("start_time", word.get("start", 0))))
                w_end = _ms_to_sec(word.get("end_time", word.get("end", w_start)))
                if start is None:
                    start = w_start
                buf.append(token)
                last_end = w_end
                if token[-1:] in ".?!。？！" or len(buf) >= 18:
                    cues.append((start or w_start, last_end, " ".join(buf)))
                    buf = []
                    start = None
            if buf and start is not None:
                cues.append((start, last_end, " ".join(buf)))
            continue

        text = str(block.get("text") or "").strip()
        if text:
            cues.append((0.0, max(1.0, len(text.split()) * 0.4), text))

    if not cues:
        # Fallback: top-level text
        text = str(data.get("text") or "").strip()
        if text:
            cues.append((0.0, max(1.0, len(text.split()) * 0.4), text))
    if not cues:
        raise ValueError("ASR 结果为空")
    return cues


async def transcribe_file_to_srt(
    audio_path: Path,
    *,
    api_key: str,
    model: str = DEFAULT_MODEL,
    language: str = "en",
) -> str:
    if not api_key.strip():
        raise ValueError("未配置阿里云百炼 ASR API Key")
    if not audio_path.exists():
        raise ValueError("音频文件不存在")

    headers = {
        "Authorization": f"Bearer {api_key.strip()}",
        "Content-Type": "application/json",
    }

    async with httpx.AsyncClient(base_url=BASE_URL, timeout=60.0) as client:
        policy_res = await client.get(
            "/api/v1/uploads",
            params={"action": "getPolicy", "model": model},
            headers=headers,
        )
        policy_res.raise_for_status()
        policy = (policy_res.json().get("data") or {})
        upload_host = policy.get("upload_host") or ""
        upload_dir = policy.get("upload_dir") or ""
        if not upload_host or not upload_dir:
            raise ValueError("阿里云 ASR 上传凭证无效")

        key = f"{upload_dir}/{audio_path.name}"
        files = {
            "OSSAccessKeyId": (None, policy.get("oss_access_key_id") or ""),
            "policy": (None, policy.get("policy") or ""),
            "Signature": (None, policy.get("signature") or ""),
            "x-oss-object-acl": (None, policy.get("x_oss_object_acl") or "private"),
            "x-oss-forbid-overwrite": (
                None,
                str(policy.get("x_oss_forbid_overwrite") or "true"),
            ),
            "key": (None, key),
            "success_action_status": (None, "200"),
            "file": (audio_path.name, audio_path.read_bytes(), "application/octet-stream"),
        }
        async with httpx.AsyncClient(timeout=120.0) as uploader:
            up = await uploader.post(upload_host, files=files)
            if up.status_code >= 300:
                raise ValueError(f"上传音频失败 HTTP {up.status_code}")

        submit = await client.post(
            "/api/v1/services/audio/asr/transcription",
            headers={
                **headers,
                "X-DashScope-Async": "enable",
                "X-DashScope-OssResourceResolve": "enable",
            },
            json={
                "model": model,
                "input": {"file_url": f"oss://{key}"},
                "parameters": {
                    "channel_id": [0],
                    "enable_itn": False,
                    "enable_words": True,
                    "language": language,
                },
            },
        )
        submit.raise_for_status()
        task_id = ((submit.json().get("output") or {}).get("task_id")) or ""
        if not task_id:
            raise ValueError("阿里云 ASR 未返回任务 ID")

        result_url = ""
        for _ in range(240):
            task = await client.get(f"/api/v1/tasks/{task_id}", headers=headers)
            task.raise_for_status()
            output = task.json().get("output") or {}
            status = output.get("task_status") or ""
            if status == "SUCCEEDED":
                result_url = (output.get("result") or {}).get("transcription_url") or ""
                break
            if status in {"FAILED", "CANCELED"}:
                raise ValueError(f"阿里云 ASR 失败：{output.get('message') or status}")
            await asyncio.sleep(0.5)
        else:
            raise ValueError("阿里云 ASR 超时")

        if not result_url:
            raise ValueError("阿里云 ASR 未返回识别结果")
        result = await client.get(result_url)
        result.raise_for_status()
        try:
            payload = result.json()
        except Exception:
            payload = result.text
        cues = _normalize_result(payload)
        return cues_to_srt(cues)
