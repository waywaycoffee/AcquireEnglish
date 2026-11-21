"""Public WeChat-friendly landing pages for cafe adventure challenges."""

from __future__ import annotations

import html

from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import HTMLResponse

from app.config import settings
from app.routers.study_desk import no_store

router = APIRouter(tags=["public-challenges"], dependencies=[Depends(no_store)])

_CAFE = [
    {
        "title": "看懂菜单",
        "ability": "读懂价目与预算",
        "prompt": "菜单：Small coffee £2 · Large coffee £3 · Small tea £2。你有 £2，想喝咖啡。选哪一款？",
        "hint": "同时满足饮品和预算。",
    },
    {
        "title": "开口点单",
        "ability": "点单 + 外带",
        "prompt": "店员问 “What can I get for you?” 你想点一杯小杯咖啡外带。",
        "hint": "To go 表示外带。",
    },
    {
        "title": "修改订单",
        "ability": "改规格 / 替换配料",
        "prompt": "你已经点了咖啡，想把牛奶换成燕麦奶。怎么说？",
        "hint": "With oat milk instead。",
    },
    {
        "title": "售罄挑战",
        "ability": "应变换单",
        "prompt": "店员说 “Sorry, we’re out of coffee.” 你想改成小杯茶，并确认外带。",
        "hint": "Then + to go。",
    },
]


def _base() -> str:
    return (
        (settings.media_public_base or "").rstrip("/")
        or "https://acquireenglish.curlhairai.com"
    )


@router.get("/public/challenges/cafe/{stage}", response_class=HTMLResponse)
async def cafe_challenge_landing(stage: int) -> HTMLResponse:
    if stage < 1 or stage > len(_CAFE):
        raise HTTPException(404, "关卡不存在")
    level = _CAFE[stage - 1]
    title = html.escape(level["title"], quote=True)
    ability = html.escape(level["ability"], quote=True)
    prompt = html.escape(level["prompt"], quote=True)
    hint = html.escape(level["hint"], quote=True)
    # Cafe adventure deep links are retired; send learners to exam prep.
    app_link = html.escape("acquireenglish://app/exam", quote=True)
    web_fallback = html.escape(
        f"{_base()}/api/public/challenges/cafe/{stage}", quote=True
    )
    install_note = html.escape(
        "未安装时可先安装爱快英语，再点「练同一关」。浏览器页不会保存成绩。",
        quote=True,
    )
    body = f"""<!doctype html>
<html lang="zh-CN"><head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta property="og:title" content="街角咖啡店 · {title}">
<meta property="og:description" content="能力目标：{ability}">
<title>街角咖啡店 · {title} · 爱快英语</title>
<style>
body{{font-family:system-ui,sans-serif;margin:0;background:#1a1520;color:#f3f4f6}}
main{{max-width:520px;margin:auto;padding:28px 20px}}
.card{{background:#2a2118;border:1px solid #ffc80066;border-radius:20px;margin:18px 0;padding:22px}}
.badge{{display:inline-block;background:#ffc800;color:#3a2a00;font-weight:800;font-size:12px;padding:4px 10px;border-radius:999px}}
h1{{font-size:26px;margin:12px 0 6px}}
p{{line-height:1.7}}
a.cta{{display:block;text-align:center;padding:16px;margin:12px 0;border-radius:14px;background:#58cc02;color:#17300b;text-decoration:none;font-weight:800}}
a.ghost{{display:block;text-align:center;padding:14px;margin:8px 0;border-radius:14px;border:1px solid #586074;color:#d5d8e0;text-decoration:none}}
small{{color:#9aa0ae}}
details summary{{cursor:pointer;color:#ffc800;font-weight:700}}
</style></head>
<body><main>
<small>ACQUIRE ENGLISH · 单人冒险</small>
<div class="card">
<span class="badge">第 {stage} 关</span>
<h1>{title}</h1>
<p>能力目标 · {ability}</p>
<p>{prompt}</p>
<details><summary>先自己想，再看提示</summary><p>{hint}</p></details>
</div>
<a class="cta" href="{app_link}">已安装 · 练同一关</a>
<a class="ghost" href="{web_fallback}">未登录也可先看题</a>
<small>{install_note}</small>
</main></body></html>"""
    return HTMLResponse(
        body,
        headers={
            "Content-Security-Policy": (
                "default-src 'none'; style-src 'unsafe-inline'; "
                "base-uri 'none'; frame-ancestors 'none'"
            ),
            "X-Content-Type-Options": "nosniff",
        },
    )
