# 内容丰富计划（当前主线）

> **优先级**：电视 / Leanback / 折叠屏 / 小程序深化 → **一律靠后**。  
> **目标**：新装用户打开 App 就能「有东西可学」，少空白、少等 ASR、少空书架。

产品模型仍是 **导入优先 + ECS 媒体**，不把音视频打进 APK。内容变厚 = **运营播种 + 推荐轨扩容 + 共享字幕/TTS/foundation 填实**。

---

## 用户能感知的「厚」长什么样

| 模块 | 现在常见体感 | 做厚后 |
|------|----------------|--------|
| 视频库 | 空库靠自己搜 B 站 | 推荐轨 + 免费种子开箱能学，字幕秒出 |
| 阅读 | 书库有链，常无声 | 精选书有封面 + 预生成朗读 |
| 零基础 / 磨耳朵 | foundation 清单空，靠合成 TTS | ECS 上有真实 demo 音视频 |
| 口语 / 句型 | syllabus JSON 有，媒体看运气 | oral/course 轨与字幕包齐 |
| 教材 / 剧集架 | 占位或网盘后才有 | 先厚推荐与免费路径；私人教材→今日课稍后 |

---

## 工作包（按性价比）

### W1 · 开箱就能学的视频轨（最先做）

1. **扩容** `services/api/data/recommended_bilibili.json`  
   - 每个方向至少 2–3 个 UP：音标 / 语调 / 口语句型 / 精听美剧讲解 / 分级故事  
   - 每条写清 `bvid`、封面、时长、`seed_pages`（先 `1` 或 `1-3`，长合集勿一次 `all`）
2. **对齐** `free_trial_seeds.json` 的 `video`（≥5，且与推荐重叠优先）  
3. **ECS 播种共享字幕**（开箱不空等 ASR）  
   ```bash
   # 见 docs/PREGEN_CACHE.md
   .venv/bin/python tools/subtitle/seed_recommended_bilibili_subs.py --dry-run
   .venv/bin/python tools/subtitle/seed_recommended_bilibili_subs.py
   ```
4. App 侧确认：推荐轨 / 免费试用入口能进播放 → 跟读 → 复习

**验收**：新账号不导入也能点开 ≥5 条可学视频，其中推荐 BV 有英/中软字幕。

### W2 · 阅读书架「有字有声」

1. 精选 3–5 本 Standard Ebooks / 分级文（含已有 Wizard of Oz）  
2. 封面：`tools/reading/seed_book_covers.py` → ECS  
3. TTS 预生成：本机 5060 Ti / CosyVoice worker → `reading/tts/`（`PREGEN_CACHE` §2）  
4. 免费种子 `reading` 模块与书库入口对齐

**验收**：阅读精选点进去能播句级朗读，不每次冷启动全量合成。

### W3 · Foundation / 磨耳朵真实媒体

1. 按 `tools/foundation_media/README.md` 上传 demo 到 `foundation/`  
2. 确认 `/api/foundation/media/*` 或 content media 清单非空  
3. 首页零基础 / 磨耳朵模块改「有声可点」，不再只靠空清单 + 本机 TTS

**验收**：未登录或新用户进学习模块能听到真实样例音。

### W4 · 考试 / 词书 / 句型补强

1. `exam_packs` 再补 1–2 套可试用卷（合规自有或授权）  
2. syllabus 空 gloss：`tools/syllabus/fill_chunks_gloss.py`  
3. `oral_core_9000` / course 字幕与 ECS `course/` 路径巡检，坏链修掉

### W5 · 结构化「每日有课」（内容→路径，稍后）

1. 私人教材 `finalize` → App `CoursePlan`（`COURSE_DECOMPOSE.md` P1）  
2. 英语之旅 Gate2 默认吃今日课程队首（`english-journey-prd.md`）  
3. 系统推荐「为什么推这条」——有内容池之后再做

> W5 依赖 W1–W3 有稳定内容池；**先灌内容，再打调度**。

---

## 明确靠后（本主线不碰）

- 电视 Leanback / 真机电视 / 折叠屏专项  
- 小程序深化、公众号菜单运营深化  
- LiveTalking 全量形象、厂商语音助手  
- K12 正版教材正文进包（继续仅目录占位 + 用户自导）

---

## 建议执行顺序（你/协作时可勾）

- [ ] **W1a** 选题：定 10–15 条 BV（合规教育向）写入 recommended + free_trial  
- [ ] **W1b** ECS 跑字幕 seed + health check  
- [ ] **W1c** 真机：新装 → 推荐/免费 → 跟读一条龙  
- [ ] **W2** 3 本精选书封面 + TTS 预生成  
- [ ] **W3** foundation 上传 ≥3 个 demo  
- [ ] **W4** exam + gloss 扫一遍  
- [ ] **W5** 教材→CoursePlan / 之旅对齐（内容池稳定后）

---

## 相关文档

| 文档 | 用途 |
|------|------|
| `docs/MEDIA_ECS.md` | 媒体命名空间与上传 |
| `docs/PREGEN_CACHE.md` | 字幕共享 / TTS / gloss |
| `docs/FREE_TIER.md` | 免费种子契约 |
| `docs/COURSE_DECOMPOSE.md` | 教材解构 → 课 |
| `docs/product/english-journey-prd.md` | 之旅与今日课程 |
| `tools/subtitle/seed_recommended_bilibili_subs.py` | 推荐 BV 字幕播种 |
| `tools/foundation_media/` | foundation 上传 |
| `tools/reading/` | 阅读 TTS / 封面 |
