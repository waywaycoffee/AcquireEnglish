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

- 真实短信 / 微信（关 mock + fluwx / 网关）— **依赖生产凭据与开放平台审核，非纯代码可结**  
- LiveKit 全双工真接线  
- 托管 oral_coach 默认 URL  
- 转写核对 draft→confirm  

## 2026-11-20 背单词模块（语境优先路线）

| 项 | 状态 |
|----|------|
| P0 FSRS 数字 / 错词本 / 掌握态 / 连续天 / 今日清完 | ✅ |
| P1 Cloze 原句卡 + 回跳视频 | ✅ |
| P1 正式拼写关卡 + 最弱环 FSRS | ✅ |
| P2 片中再遇 + 软巩固 | ✅ |
| P2 7 日统计 + 热力图 | ✅ |
| P2 背词 speak → 腾讯云 SOE | ✅ 代码已接；需本机/CI 配置密钥，见 `deploy/TENCENT_SOE_SETUP.md` |
| 今日背词单词专属会话 / 错词本会话 / 复习上限 | ✅ `?kind=word` · `?deck=missed` · `dailyReviewLimit` |
| 词详情「复习此词」· 掌握阶段汇总 · 配额同步 | ✅ |
| 考纲词书（四级/六级自建 + CSV/TXT 导入） | ✅ v1 已交付；卡通配图词书仍不做 |
| 在线词库 lilinji/English 按需下载 | ✅ 用户自选分类下载到本机词书 |
| 爱快阅读（App 内模块 v1） | ✅ 导入 TXT/EPUB · 内置样例 · 视频字幕生成 · 点词进词书 |
| 真机覆盖安装 | ⛔ 签名不一致（需与机上同 keystore） |


## 2026-11-16 审计更新（优先于上文旧状态）

项目处于功能整合与稳定性收敛阶段，移动端是主要产品载体。近期已增加真实短信/微信适配、新用户试用资产、跟读自动评分、趣配音分享、数字人连接修复和 Ollama 公网翻译。旧表中的“无 fluwx”“真实登录未接线”已过时，但代码完成不等于生产验收。

### 本次验证证据

- API 七组本地测试通过：feature_matrix、phone_wechat_auth、user_assets、rewards、shared_subtitles、personal_import_assets、bilibili_search，共 27 passed。
- Web：npm.cmd run build 通过 TypeScript 检查及 Vite 构建。
- 当前 PATH 无 Flutter，移动端测试、分析、打包及真机流程未验证。
- 未验证生产环境或真实供应商。账号测试启用 mock；API 配置默认短信/微信 mock 为 true，生产实际值待核对。
- Web 学习页仍存在 DEMO 字幕回退，真实课程失败时的行为需收敛。
- 根目录未发现 GitHub Actions 工作流，需补持续验证。

### 下一迭代 P0：发布基线（约 5–8 人日，外部平台等待另计）

1. 建立并执行核心闭环检查表（1–2 日）：登录→导入→字幕补齐→播放→收藏→跟读→复习→另一设备同步。记录版本、设备、素材、结果及缺陷。
2. 真实登录验收（1–2 日）：核对生产开关与凭据，验证短信发送、错误码、限流，微信授权、取消和失败；真实模式不返回 debug_code。
3. 根据闭环结果修复字幕与录音阻断问题（2–3 日）：重点验证弱网、超时、后台切换、权限拒绝、重试、取消及录音恢复。
4. 建立 API 测试、Web build、Flutter analyze/test 持续检查（1 日）；网络、GPU、真机测试独立执行；更新功能矩阵执行记录。

验收门槛：Android 真机核心路径完成；iOS 单独记录验收或阻塞原因；常规自动检查通过；无未解决的登录、播放或数据丢失阻断问题。

### 第二迭代 P1：数据与体验一致性

1. 验证同步冲突规则、离线重试、幂等及切换账号隔离；逐项核实单词、短语、句子、进度和偏好，缺失项再补。
2. Web 真实课程取消静默示例字幕回退，提供失败提示和重试；确定最小跨端功能范围。
3. 选定口语主路径，验收真实 ASR/LLM/TTS、反馈写入及复习回流；核实 draft→confirm 实现情况后补齐。
4. 验证资产扣减、并发重复请求、到期和失败返还，确保客户端与 API 一致。

验收门槛：跨设备学习结果一致；真实课程不出现示例字幕；口语反馈进入复习；额度显示与服务端一致。

### P2：核心稳定后扩展

明确 LiveKit 与 LiveTalking 职责后推进全双工、数字人真推理、延迟与断线恢复；任务地图、音素可视化、多人格按用户反馈排序。账号绑定、找回与运维能力根据真实使用需求调整优先级。

下一项具体工作：恢复 Flutter 工具链，运行现有移动端测试，并建立核心闭环验收记录。以上排期为单人粗估，根据首轮缺陷数量调整。
