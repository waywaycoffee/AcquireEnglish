# AcquireEnglish 验收报告 — 2026-11-15

**Verdict: PASS**（服务端 / Web / 口语教练 / LiveTalking / Postgres）  
App 客户端条目因本机无真机未测，记为 **N/A**，不阻塞本次生产验收。

## 范围与依据

- Checklist: `deploy/ACCEPTANCE_CHECKLIST.md`
- 自动化: `services/api/tests/test_prod_e2e_suite.py` → **21 passed / 0 failed**
- Web UI: 浏览器手工走通登录 → 课程 → 偏好 → 导入
- LiveTalking: aiortc E2E + Tailscale 浏览器 UI 连接

## 结果摘要

| 区域 | 结果 | 证据 |
|------|------|------|
| API / Health | pass | `status=ok`, SMS/WeChat mock flags true |
| 注册 / 登录 | pass | `qa_accept_1794673159@example.com` |
| 课程 / 播放器 | pass | `slow-english-demo` 字幕与词卡可用；演示视频 CDN 待替换（已知） |
| 进度 | pass | play → `position_sec≈16.8`；API PUT/GET `42.5` |
| 词卡 / 词汇本 | pass | 课内词卡 18 条；API vocab `acceptance` |
| 偏好 / 今日更新 | pass | UI 保存后 feed 变为 TED + 慢速故事 |
| B 站导入 | pass | `link-6` 出现在课程列表 |
| Oral coach | pass | draft / confirm / turn（suite） |
| LiveKit | pass | `wss://…livekit.cloud` + token；Agent schtask Running |
| LiveTalking | pass | WebRTC frames + 浏览器「已连接」+ glass_man 画面 |
| Postgres | pass | API 使用 PG；users=29；偏好重登持久化 |
| Auth SMS/WeChat | mock-mode pass | 按 checklist §0 接受 |
| App settings | N/A | 无设备 |

## Ops 快照（~00:21 UTC+8）

- ECS: `acquireenglish-api` / `oral-coach` / `postgresql` / `nginx` → **active**
- LiveTalking: `http://100.115.252.55:8010` → **200**，WebRTC 可连
- Windows: `AcquireEnglish-LiveKit-Agent` → **Running**

## 已知非阻塞项

1. 演示课视频文案仍提示 CDN 待替换；字幕与控制已可用。
2. Web 无独立「粘贴 SESSDATA」设置页；API 仅暴露 `has_bilibili_cookie`（不回显密钥）。
3. 微信 / 短信仍为 mock，待真实密钥再切真登录。
4. App 冷启动 / 进房 / 口语入口需真机补验。

## 结论

生产核心链路（认证、课程、进度、偏好、导入、教练、LiveKit token、Tailscale 数字人唇形、Postgres）已验收通过，可按生产态对外演示。App 端补测不改变本次服务端签收。
