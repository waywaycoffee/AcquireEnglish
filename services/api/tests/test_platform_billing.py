"""Platform billing key discovery (no live vendor calls)."""

from __future__ import annotations

import os
from pathlib import Path

import pytest

from app.services import platform_billing as pb


def test_discover_keys_includes_multiple_platforms(monkeypatch, tmp_path: Path):
    coach = tmp_path / "oral_coach.env"
    coach.write_text(
        "\n".join(
            [
                "DEEPSEEK_API_KEY=sk-deepseek-test-key-1234",
                "DEEPGRAM_API_KEY=dg-test-key-abcd",
                "DASHSCOPE_API_KEY=sk-dash-test-9999",
                "LIVETALKING_URL=http://100.115.252.55:8010",
            ]
        ),
        encoding="utf-8",
    )
    monkeypatch.setattr(pb, "_ENV_CANDIDATES", (coach,))
    for name in (
        "DASHSCOPE_API_KEY",
        "DEEPSEEK_API_KEY",
        "DEEPGRAM_API_KEY",
        "OPENAI_API_KEY",
        "TENCENT_SOE_SECRET_ID",
        "LIVEKIT_API_KEY",
    ):
        monkeypatch.delenv(name, raising=False)

    keys = {k["id"]: k for k in pb.discover_keys()}
    assert keys["deepseek"]["configured"] is True
    assert keys["deepgram"]["configured"] is True
    assert keys["dashscope"]["configured"] is True
    assert keys["livetalking"]["configured"] is True
    assert keys["local_gpu_ollama"]["configured"] is True
    assert "…" in (keys["deepseek"]["key_label"] or "")
    # Never leak full secret
    blob = str(keys)
    assert "sk-deepseek-test-key-1234" not in blob
    assert "dg-test-key-abcd" not in blob


def test_module_label_zh():
    assert "口语" in pb.module_label_zh("oral_coach")
    assert pb.module_label_zh("nope") == "nope"


def test_collect_platform_usage_keyword_only(monkeypatch):
    monkeypatch.setattr(pb, "discover_keys", lambda: [])
    monkeypatch.setattr(
        pb,
        "fetch_aliyun_bss",
        lambda month=None: {"ok": False, "products": {}, "balance_cny": None},
    )
    monkeypatch.setattr(
        pb,
        "fetch_tencent_billing",
        lambda month=None: {"ok": False, "items": []},
    )
    monkeypatch.setattr(pb, "fetch_livekit_note", lambda: {"configured": False})
    monkeypatch.setattr(pb, "fetch_deepgram_usage", lambda: {"ok": False, "projects": []})
    monkeypatch.setattr(pb, "fetch_deepseek_note", lambda: {"configured": False})
    monkeypatch.setattr(
        pb,
        "fetch_gpu_usage",
        lambda: {"ok": False, "by_module": [], "total_tokens": 0},
    )
    out = pb.collect_platform_usage(month="2026-11")
    assert out["ok"] is True
    assert out["billing_cycle"] == "2026-11"
    assert "gpu" in out
    assert "deepgram" in out


def test_fetch_aliyun_bss_never_uses_sms_keys(monkeypatch, tmp_path: Path):
    env_file = tmp_path / "api.env"
    env_file.write_text(
        "\n".join(
            [
                "ALIYUN_SMS_ACCESS_KEY_ID=LTAI5tSmsOnlyKeyXXXX",
                "ALIYUN_SMS_ACCESS_KEY_SECRET=sms-secret-should-not-be-used",
            ]
        ),
        encoding="utf-8",
    )
    monkeypatch.setattr(pb, "_ENV_CANDIDATES", (env_file,))
    for name in (
        "ALIYUN_BSS_ACCESS_KEY_ID",
        "ALIYUN_BSS_ACCESS_KEY_SECRET",
        "ALIYUN_ECS_ACCESS_KEY_ID",
        "ALIYUN_ECS_ACCESS_KEY_SECRET",
        "ALIYUN_ACCESS_KEY_ID",
        "ALIYUN_ACCESS_KEY_SECRET",
        "ALIYUN_SMS_ACCESS_KEY_ID",
        "ALIYUN_SMS_ACCESS_KEY_SECRET",
        "ALIYUN_BSS_QUERY_BALANCE",
    ):
        monkeypatch.delenv(name, raising=False)

    called: list[str] = []

    def _fake_call(action, params, *, ak, sk):  # noqa: ANN001
        called.append(action)
        return {"Success": True, "Data": {"AvailableAmount": "1"}}

    monkeypatch.setattr(pb, "_aliyun_bss_call", _fake_call)
    out = pb.fetch_aliyun_bss(month="2026-11")
    assert out["ok"] is False
    assert "短信" in out["error"] or "BSS" in out["error"]
    assert called == []


def test_fetch_aliyun_bss_skips_balance_by_default(monkeypatch, tmp_path: Path):
    env_file = tmp_path / "api.env"
    env_file.write_text(
        "\n".join(
            [
                "ALIYUN_BSS_ACCESS_KEY_ID=LTAI5tBssOnlyKeyYYYY",
                "ALIYUN_BSS_ACCESS_KEY_SECRET=bss-secret",
            ]
        ),
        encoding="utf-8",
    )
    monkeypatch.setattr(pb, "_ENV_CANDIDATES", (env_file,))
    for name in (
        "ALIYUN_BSS_QUERY_BALANCE",
        "ALIYUN_SMS_ACCESS_KEY_ID",
        "ALIYUN_SMS_ACCESS_KEY_SECRET",
    ):
        monkeypatch.delenv(name, raising=False)

    called: list[str] = []

    def _fake_call(action, params, *, ak, sk):  # noqa: ANN001
        called.append(action)
        if action == "QueryBillOverview":
            return {"Data": {"Items": {"Item": []}}}
        if action == "DescribeInstanceBill":
            return {"Data": {"Items": {"Item": []}}}
        return {"Success": True, "Data": {}}

    monkeypatch.setattr(pb, "_aliyun_bss_call", _fake_call)
    out = pb.fetch_aliyun_bss(month="2026-11")
    assert "QueryAccountBalance" not in called
    assert out.get("balance_cny") is None
    assert "balance_note" in out
