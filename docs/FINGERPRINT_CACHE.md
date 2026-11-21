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
4. 任务 `success`；App 轮询 `GET /api/fingerprint-cache/upload-tasks/{id}`，就绪后拉取 asset 并加课

### Degraded（向量库不可用）

- Search 返回 `degraded=true` + `candidates`
- 任务 `pending_confirm`
- App 弹窗确认后 `POST /api/fingerprint-cache/confirm-bind`

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

URL 不可达时 API 回退 hashing-trick；此时命中会降级为需确认的 SimHash 候选。

## 手动排空队列

API 启动后后台会自动 drain。也可：

```bash
# 管理端
curl -X POST -H "X-Admin-Token: …” \
  "https://acquireenglish.curlhairai.com/api/admin/fingerprint-cache/drain-queue?limit=5"

# 或本机 CLI（在 API 环境）
cd services/api
.venv/Scripts/python.exe -m app.services.fingerprint.cli_drain
```

## Share / audit

- `POST /api/fingerprint-cache/my-courses/{id}/share` — 标记待审
- `POST /api/admin/fingerprint-cache/share-audit/{id}` — 通过/拒绝 stub

## 约束

- 音视频只存 ECS，不进 APK
- 解构优先走 `OPENMAIC_URL`（OpenMAIC / `tools/openmaic_mock`）；不可达时回退 CPU 启发式。详见 `docs/COURSE_DECOMPOSE.md`
