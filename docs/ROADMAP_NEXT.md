# AcquireEnglish 后续开发计划（2026-11-14）

依据当前代码与生产环境 `https://acquireenglish.curlhairai.com` 的审计结果。

## 现状摘要

| 层 | 状态 |
|----|------|
| 账号 API（邮箱/手机/微信端点） | 已上线；短信/微信仍为 **mock**（可自动注册） |
| App 登录 UI | 有；微信无 fluwx，正式 AppID 会报错 |
| 进度 / 每日课同步 | 可用 |
| 词库云同步 | **半残**：拉取有，收藏推送多数路径未调 |
| 「备份同步云端」按钮 | **假的**（仅 Toast） |
| 偏好 bilibili/asr key | Schema/DB 有，**路由未读写** |
| oral_coach HTTP 回合 | 可用（默认 mock providers） |
| ChatterPal 学习层 | 后端可用，**App/Agent 未接** |
| LiveKit 全双工 | **骨架**，与 App 断开 |

## 优先级

### P0（本迭代开发）

1. 设置「备份同步」接真实 progress + vocab 同步  
2. 收藏/加词时 `vocabSync.pushEntry`  
3. API preferences 持久化 bilibili_cookie / asr_api_key；App DTO 对齐  
4. 学习闭环挂到生产 API：`/api/learning/*`（复用 JWT）  
5. App：学习客户端 + 口语陪练 Tab 展示反馈/错题入口  
6. 发音：可用的 `simple` 词重叠打分（无 GPU）；可选第三方 HTTP 适配口  

### P1（下一迭代）

1. 真实短信网关 + 关 `AUTH_SMS_MOCK`；验证码改 SQLite  
2. fluwx 微信登录 + 关 `AUTH_WECHAT_MOCK`  
3. 托管 oral_coach（Deepgram/Edge/LLM）并设 App 默认 URL  
4. 转写核对（draft → confirm）再进 LLM  
5. WhisperX 词级对齐 / 第三方口语评测 API 真接  
6. 句子收藏 / phrases 云同步  

### P2

1. LiveKit Agents 真正接线 oral_coach + learning + DataChannel 分数  
2. MuseTalk / LivePortrait 真推理  
3. 任务地图、音素可视化、多人格、账号绑定/找回密码  

## 本迭代验收

- [x] 登录后点「备份同步」会请求进度与词库接口（非假 Toast）  
- [x] 收藏单词后云端 push（`toggleFavorite` / `addFavoriteWord`）  
- [x] `PUT /api/preferences` 可保存并回显 has_bilibili_cookie / has_asr_api_key（已上线）  
- [x] `POST /api/learning/sessions` + 错题列表在生产域名可用  
- [x] 口语陪练回合后写入学习层并展示反馈 /「存入复习」  
- [x] 发音 `simple` + `http` 第三方适配口  

## 未完成（明确留给下一迭代）

- 真实短信 / 微信（关 mock + fluwx / 网关）  
- LiveKit 全双工真接线  
- 托管 oral_coach 默认 URL  
- 转写核对 draft→confirm  

