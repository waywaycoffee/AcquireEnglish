# 微信小程序 v1（轻量化 AcquireEnglish）

> 定位：**碎片学习入口 + 字幕预约台 + 导流 App 精听**。  
> 与 App 共用账号与 ECS API；不做完整播放器、本地导入、FFmpeg/OCR/Whisper。

---

## 1. 产品边界

| 小程序做 | App 做 |
|----------|--------|
| 今日 FSRS 复习、预约字幕与进度 | 精听播放器、单句循环、配音导出 |
| 云端轻阅读、瘦口语回合 | 本地/网盘导入、MKV/软硬字幕管线 |
| 登录、打卡摘要、打开 App | 数字人、LiveKit 真人对练、Anki 导出 |

**主路径**：打开小程序 → 刷今日复习 →（可选）预约 B 站字幕 → 通知到达 → 打开 App 精听。

---

## 2. 信息架构（六 Tab）

| Tab | 目标 | 主界面 |
|-----|------|--------|
| **首页** | 今天干什么 | 待复习数、预约进行中、打卡/成长、打开 App |
| **复习** | 刷完今日 FSRS | 到期队列 → 卡片评分 → 结束页 |
| **预约** | 下单字幕并盯进度 | 粘贴链接 / 我的列表 / 状态详情 |
| **阅读** | 碎片读短文 | 书库 → 正文点词 → TTS |
| **口语** | 说几轮场景句 | 场景 → 录音 → 云端反馈 |
| **我的** | 账号与导流 | 资料、会员、统计、打开 App |

### 2.1 首页

- 待复习 N（进复习）
- 预约：进行中 / 今日完成（进预约）
- 今日学习分钟、连续打卡、成长值（只读）
- CTA：打开 App 精听（通用深链）

### 2.2 复习（FSRS）

- 队列类型：词、短语、听写项；**带视频时间轴的跟读项**仅展示「去 App 跟读」
- 操作：Again / Hard / Good / Easy；可播 TTS
- 结束页：完成数、正确率倾向、下次到期、分享打卡卡
- **前提**：复习状态上云（App 现以本机 FSRS 为主，见 §4 新增 API）

### 2.3 预约字幕

- 粘贴 B 站单集/合集 URL（或精选入口）→ `reserve: true` 入队
- 列表状态：排队中 / 生成中 / 已完成 / 失败可重试
- 完成后：微信订阅消息 + 「去 App 学本集」深链（bvid + page）
- **不做**：本机下载、MKV、ASR/OCR

### 2.4 阅读

- 在线目录/短文 → 正文 → 点词（public-lexicon）→ 可加入复习
- 云端 TTS（`/api/reading/speech`）
- **不做**：本地 EPUB/PDF OCR

### 2.5 口语

- 场景列表 → 用户录音 → 云端 ASR / 评分 / TTS 回句
- **不做**：数字人形象、真人对练、拍照识词

### 2.6 我的

- 微信登录账号、`GET /api/auth/me`
- 会员说明 / 支付（可二期）
- 打开 App、关于与反馈

---

## 3. 接口清单

### 3.1 已有（直接或薄封装）

| 能力 | 方法 |
|------|------|
| 微信登录 | `POST /api/auth/wechat/login` |
| 当前用户 | `GET /api/auth/me` |
| 预约/生成字幕 | `POST /api/shared-subtitles/jobs`（body 含 `bvid`、`page`、`reserve: true`） |
| 翻译队列 | `POST /api/shared-subtitles/translate-jobs` |
| 任务状态 | `GET /api/shared-subtitles/jobs/{job_id}` |
| 查共享字幕 | `GET /api/shared-subtitles/bilibili`、`/bilibili/list` |
| 查词 | `GET /api/public-lexicon/{word}`、`/{word}/audio` |
| 阅读 | `/api/reading/*`、`/api/reading/speech` |
| 日更精选（可选） | `GET /api/feed/daily` |

> 微信小程序登录若与 App 的 `wechat/login` code 体系不同，需增加 **小程序专用 code2session** 换 JWT（实现时与现有 `wechat_openid` 绑定同一用户）。

### 3.2 第一期建议新增

#### 复习（云端 FSRS）

```
GET  /api/review/due
  → { items: [{ id, key, kind, front, back, tts_url?, deep_link? }], total }

POST /api/review/grade
  body: { id|key, rating: again|hard|good|easy }
  → { next_due_at, remaining_today }

GET  /api/review/today-summary
  → { due_count, done_count, streak_days, study_minutes_today }
```

- `key` 与 App `ReviewRecord.key`（如 `entry:` / `syllabus:`）对齐，便于双端同步。
- 首版可先：**小程序读写云端副本；App 登录后拉取合并**（冲突策略：以较新 `reviewed_at` 为准）。

#### 预约列表

```
GET /api/shared-subtitles/reservations?mine=1
  → { items: [{ job_id, bvid, page, title?, status, created_at, updated_at, error? }] }
```

底层可查现有 `gpu-subtitle-jobs` 按 `user_id` 过滤。

#### 深链与通知

| 项 | 说明 |
|----|------|
| App 深链 | 如 `acquireenglish://episode?bvid=&page=` / 通用 https 中间页 |
| 订阅消息 | 任务 `completed` 时服务端发微信订阅（需小程序模板 ID 配置） |

#### 口语回合（若尚无稳定 HTTP）

```
POST /api/oral/turn
  multipart: scene_id, audio
  → { asr_text, score?, reply_text, tts_url }
```

优先复用现有 oral_coach / 相关路由，避免重复造轮子。

### 3.3 第二期

- 考试薄包、社区 feed、会员微信支付、写作批改  
- 云端课表「仅已出字幕集」浏览  

---

## 4. 落地顺序

1. **登录 + 首页壳 + 打开 App**（含小程序微信登录若需新 endpoint）  
2. **预约字幕**（复用 jobs；补 `reservations` 列表 + 订阅消息）  
3. **FSRS 云同步 + 复习页**（第一期最大后端工作）  
4. **阅读** → **口语** → 分享打卡卡  

---

## 5. 非目标（v1）

- 小程序内完整精听 UI、本地文件导入、网盘、MKV 处理  
- 硬字幕 OCR、本机 Whisper、配音导出  
- LiveKit / 数字人形象渲染  

---

## 6. 相关文档

- 总功能说明：`docs/product/PRODUCT_FEATURES.md`  
- 媒体原则：`docs/MEDIA_ECS.md`  
- 共享字幕 / GPU 队列：`services/api` → `shared_subtitles`、`gpu_subtitle_queue`
