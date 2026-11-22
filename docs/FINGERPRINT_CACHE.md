# 素材指纹缓存复用

同源教材导入时，先算指纹检索公共 `asset_cache`；命中则秒出课程结构，未命中则排队轻量解构并写入缓存。

## 流程

### Hit

1. App `POST /api/fingerprint-cache/search`（登录）
2. API SimHash 分带召回 + BGE/本地向量交叉校验
3. 自动 `user_course_asset` 绑定，返回 `asset`（含 `lessons`）
4. Flutter 把 lessons 写入本地阅读库并打开，**不再**只做 SnackBar

### Miss

1. 创建 `upload_task`，状态 `queue_gpu`
2. 文本载荷写入 ECS `media/course/upload_task/{id}/payload.json`（仅清理后正文，无 PDF/音视频）
3. API 进程内 `fingerprint.queue_worker` 认领 → `decompose_text_to_lessons` → `register`
4. 任务 `success` + `notify_pending=1`；App 首页拉取 `/notifications` 提示，或轮询 `GET /upload-tasks/{id}`

### Degraded（向量库不可用）

- Search 返回 `degraded=true` + `candidates`
- 任务 `pending_confirm`
- App 弹窗确认后 `POST /api/fingerprint-cache/confirm-bind`

### 同步公共版

私有课若关联了 `asset_cache_id`，可在编辑页点「同步公共版」：

`POST /api/fingerprint-cache/my-courses/{id}/sync-public` — 丢弃私有课时 overlay，恢复公共结构。

## 本机 Embedding（5060 Ti）

```powershell
cd D:\AcquireEnglish\tools\fingerprint_embed
.\start.ps1
```

- Health: `http://127.0.0.1:8092/health`
- Tailscale: `http://100.115.252.55:8092/health`
- ECS `.env`:

```
FINGERPRINT_EMBED_URL=http://100.115.252.55:8092/embed
FINGERPRINT_EMBED_DIM=512
```

URL 不可达时 API 回退 hashing-trick。

## 向量库（Qdrant 可选）

```
FINGERPRINT_QDRANT_URL=http://127.0.0.1:6333
# FINGERPRINT_QDRANT_API_KEY=...
```

- 配置后写入/检索走 Qdrant collection `asset_embedding`，并仍镜像本地 JSON。
- 未配置或 Qdrant 宕机：本地 JSON 暴力检索；`vector_store_available()==false` 时走 degraded 确认流。

## 配置持久化

Admin `PATCH /api/admin/fingerprint-cache/config` 写入  
`media/misc/fingerprint_runtime_config.json`，API 启动时加载。

后台 worker 按 `fingerprint_lru_interval_seconds`（默认 86400）自动 LRU。

## 管理端

Admin Web →「指纹缓存」页：命中率 / GPU 节省估算 / TOP / 下架 / 排空队列 / LRU / 阈值。

## 验收脚本

```bash
cd services/api
python tools/fingerprint_acceptance.py
```

判定：同源召回 ≥90%、误命中=0、P95 ≤200ms（本机空库 smoke）。

## 手动排空队列

```bash
curl -X POST -H "X-Admin-Token: …” \
  "https://acquireenglish.curlhairai.com/api/admin/fingerprint-cache/drain-queue?limit=5"
```

## Share / audit

- `POST .../share` — 501 P2 stub
- Admin share-audit — 状态翻转 stub

## 约束

- 音视频只存 ECS，不进 APK
- 解构优先走 `OPENMAIC_URL`；不可达时回退 CPU 启发式。详见 `docs/COURSE_DECOMPOSE.md`
