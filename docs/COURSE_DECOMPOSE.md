# 教材智能解构（课程模块）

用户上传 EPUB/PDF → 清洗 → SUBTLEX 频次 + CEFR → 切课 → 阅读 + 词汇热身任务包 → **仅私人课程库**。  
本模块**优先复用**已有指纹缓存 / 阅读导入，不另起平行栈。社区广场分享为 **P2**，P0 不启用公开发布。

## PRD → 现有能力映射

| PRD 能力 | 落点（已有 / P0 扩展） | 说明 |
|----------|------------------------|------|
| 上传 EPUB/PDF | App `reading_ingest` / `reading_pdf_import` | 客户端抽正文（含 OCR）；不进 APK 媒体资源 |
| 清洗 boilerplate | `clean_material_text`（P0）+ 既有字幕清洗启发 | 页眉页脚、重复行、空白压缩 |
| 指纹复用 | `POST /api/fingerprint-cache/search` | 命中 → 绑定 `UserCourseAsset` + `ReadingDoc` |
| Miss 解构 | `queue_gpu` → `decompose_and_annotate` | OpenMAIC（若 `OPENMAIC_URL`）→ 失败回退启发式 |
| 私人课库 | `GET /api/fingerprint-cache/my-courses` | `UserCourseAsset`；`is_shared=false` 默认 |
| 切课预览/编辑 | `GET/PATCH …/my-courses/{id}` + `/lessons`（P0） | merge / split / delete / 改目标词 |
| 词频 + CEFR | `annotate` + `cefr_from_freq_rank`（对齐 App `cefrFromFreqRank`） | 可选读 `public-lexicon`（SUBTLEX） |
| 任务包 | 每课 `goal` + `target_words` 3–8 + `tasks[]` | reading + vocab_warmup + oral/shadow（OpenMAIC 时） |
| 版权免责 | 上传需 `license_ack`；文案固定 | 用户自负；**无自动发布** |
| 共享 OCR | `shared-ocr-books` | 私人解构流默认 **不上传** OCR（`share_ocr=false`） |
| OpenMAIC 编排 | `OpenMaicSplitter` HTTP 客户端 | 已对接；见下方「OpenMAIC」 |
| 每日课程 | lessons 结构兼容 `lesson_no` / `goal` / `cefr` | 后续日程编排消费同一 JSON |
| 社区分享 | `POST …/share` 仅 stub | **P2**；App P0 不暴露入口 |

## 数据流（P0）

```
App 选 PDF/EPUB
  → 本地解析（可选 OCR；private 流不 put shared-ocr）
  → POST /fingerprint-cache/search { cleaned_text, private_only: true }
       ├─ hit  → UserCourseAsset + lessons → 阅读库 /「我的教材课」
       └─ miss → upload_task(queue_gpu, private_only)
                  → decompose_and_annotate（OpenMAIC 或启发式 + CEFR/wordbank）
                  → register_private_user_course（不写公共 asset_cache）
                  → App 轮询 upload-tasks → 预览切课 → PATCH lessons → 确认入库
```

`private_only=true`（默认教材流）：只写用户私有 `UserCourseAsset`（`asset_cache_id=null`，课结构在 `diff_patch_json`），**不**注册全局 `asset_cache` / fingerprint，避免用户版权素材进入公共复用池。

同源公开复用仍走既有 `private_only=false` 路径（阅读库「导入读物」可选用）。

## API（P0）

| 方法 | 路径 | 作用 |
|------|------|------|
| POST | `/api/fingerprint-cache/search` | +`private_only`（默认 false 兼容旧客户端） |
| GET | `/api/fingerprint-cache/my-courses` | 私人教材课列表 |
| GET | `/api/fingerprint-cache/my-courses/{id}` | 详情 + 合并后的 lessons |
| PATCH | `/api/fingerprint-cache/my-courses/{id}/lessons` | merge/split/delete/edit/replace |
| POST | `/api/fingerprint-cache/my-courses/{id}/finalize` | 确认课包（状态 ready，可供阅读/每日课） |
| GET | `/api/fingerprint-cache/upload-tasks/{id}` | 异步任务状态 |
| POST | `/api/fingerprint-cache/my-courses/{id}/share` | **P2 stub**，App 不调用 |

## 课结构（兼容每日课程）

```json
{
  "lesson_no": 1,
  "title": "Lesson 1 · A quiet morning",
  "text_content": "...",
  "cefr": "A2",
  "goal": "理解段落大意并掌握 5 个目标词",
  "target_words": [
    {"word": "quiet", "rank": 1200, "cefr": "A2"}
  ],
  "oral_outline": ["用三句话复述主旨", "用两个目标词回答同伴提问"],
  "shadow_lines": ["A quiet morning began with birdsong."],
  "tasks": [
    {"type": "reading", "title": "精读本课"},
    {"type": "vocab_warmup", "title": "词汇热身", "word_count": 5},
    {"type": "shadow", "title": "跟读影子读", "line_count": 1},
    {"type": "oral_outline", "title": "口语提纲练习", "prompt_count": 2}
  ]
}
```

## 版权与合规

- 上传确认：用户保证仅供个人学习或已获授权；平台不审核版权实体。
- P0 **禁止**自动进社区广场 / 公共 `asset_cache`（`private_only`）。
- 原文 PDF/EPUB **不**进 APK；服务端 miss 载荷仅存清洗后正文 JSON（`media/course/upload_task/…`）。
- 音视频一律 ECS namespace；本模块 P0 无 TTS/ASR。

## 分期

### P0（本迭代）

- [x] 设计文档映射 PRD → fingerprint / reading
- [x] `decompose` 输出 CEFR + 3–8 目标词 + reading/vocab tasks
- [x] `private_only` 私人入库，不写公共指纹池
- [x] 切课 PATCH（merge/split/delete/edit）+ finalize
- [x] App「我的教材课」+ 预览编辑 + 阅读入口；OCR 默认不共享
- [x] OpenMAIC 适配器接口（启发式实现）
- [x] 单元测试 annotate / splitter / private path

### P1

- [x] OpenMAIC HTTP 对接（`OPENMAIC_URL` + soft-fallback）
- 服务端 PDF/EPUB 直传抽取；扫描件 ASR/对齐走本机 5060 Ti
- 口语跟读任务挂 oral_coach；TTS 走 ECS `reading` namespace
- 「每日课程」日程消费私人课包

## OpenMAIC（P1 已接线）

上游产品：[THU-MAIC/OpenMAIC](https://github.com/THU-MAIC/OpenMAIC)（多代理互动教室）。本仓库**不** vendoring 其 Next.js 全栈；API 通过 `OpenMaicSplitter` 远程调用。

### 配置（`services/api`）

| Env | 含义 |
|-----|------|
| `OPENMAIC_URL` | 基址；空 = 仅启发式 |
| `PREFER_OPENMAIC` | 默认 `true`；有 URL 时优先走 OpenMAIC |
| `OPENMAIC_TIMEOUT_SECONDS` | 单次 HTTP 超时（默认 45） |
| `OPENMAIC_POLL_TIMEOUT_SECONDS` | 原生 generate-classroom 轮询上限（默认 180） |
| `OPENMAIC_ACCESS_CODE` / `OPENMAIC_BEARER_TOKEN` | 自托管 cookie / Live Demo Bearer |

私人上传路径：**OpenMAIC 任意失败 → `HeuristicSplitter`**，不把任务打成硬失败。

### 两种远端模式（自动探测）

1. **AcquireEnglish decompose 合同**（教材切课主路径）

```http
POST {OPENMAIC_URL}/api/v1/decompose
Content-Type: application/json

{
  "cleaned_text": "...",
  "asset_name": "NCE Book1",
  "constraints": {
    "min_lesson_chars": 160,
    "max_lesson_chars": 2800,
    "include_oral_outline": true,
    "include_shadow": true
  }
}
```

响应：`{ "lessons": [{ "lesson_no", "title", "text_content", "goal?", "target_words?", "oral_outline?", "shadow_lines?" }] }`  
随后本地 `annotate_lessons` 补 CEFR / 词频 / reading+vocab（+ oral/shadow tasks）。

2. **原生 OpenMAIC**（探测到 `GET /api/generate-classroom/capabilities`）  
   `POST /api/materials`（text/plain）→ `POST /api/generate-classroom` → 轮询 → scenes/outline 映射为 lessons。

### 本机 / GPU 盒运行

**A. 官方 OpenMAIC（推荐生产，5060 Ti 盒，端口 3000）**

安装路径在仓库外：`D:\OpenMAIC`（MIT，不进 git）。详见 `tools/openmaic/README.md`。

```powershell
cd D:\AcquireEnglish\tools\openmaic
.\start.ps1   # 需保持运行；自动开 ECS Postgres SSH 隧道 :5433
```

- UI / API: `http://127.0.0.1:3000`
- Tailscale: `http://100.115.252.55:3000`
- Capabilities: `GET /api/generate-classroom/capabilities`
- ECS `.env`: `OPENMAIC_URL=http://100.115.252.55:3000`

`start.ps1` 用 DeepSeek（复用 `tools/oral_coach/.env`）+ ECS Postgres 隧道。OpenMAIC 本体走云端 LLM HTTP，不强制 CUDA；本机 Ollama/FunASR 可选。

**B. Mock 回退（可选，端口 8093）**

官方进程宕机时临时切 mock：

```powershell
cd D:\AcquireEnglish\tools\openmaic_mock
# 可选：DEEPSEEK_API_KEY / DASHSCOPE_API_KEY 启用 LLM 切课
.\start.ps1
```

- Health: `http://127.0.0.1:8093/api/health`
- 临时：`OPENMAIC_URL=http://100.115.252.55:8093`

无 LLM key 时 mock 用启发式切课；adapter 自动探测 mock vs 原生。

### 测试

```bash
cd services/api
pytest tests/test_openmaic_adapter.py -q
```

### P2

- 社区分享 / 审核广场（现有 share stub 接产品）
- 教材作者页、协作编辑、公开词表贡献

## 复用约束（勿重复造轮）

1. 切课核心继续调用 `decompose_text_to_lessons`（可换 adapter）。
2. 命中复用继续 `search` → `create_user_course_from_cache`。
3. App 阅读呈现继续 `ReadingDoc` / `readingDocsFromFingerprintAsset`。
4. 词级 CEFR 与 App `cefrFromFreqRank` 阈值阈值保持一致。
5. 不引入第二套 UserMaterial 表，除非 P1 需要原文二进制托管审计。
