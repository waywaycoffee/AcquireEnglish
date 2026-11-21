# 换机无感同步（一期）

登录或前台恢复后，同一账号自动拉齐学习数据；音视频仍只走 ECS / 原链重下，不打进 APK。

## 触发

- 登录成功 / token 变化：`cloudCatalogSyncProvider` → `syncCloudCatalogAndFeed`
- App resume：`DailyFeedLifecycleHost` 使上述 provider 失效并等待
- 设置页「备份同步云端数据」：`syncCloudCatalogAndFeed(pushLocal: true)`
- 本地编辑阅读书架 / 词书 / 学习设置：idle 任务 `IdleJobKind.cloudSync`（push+pull）

## 域与冲突

| 域 | API | 策略 |
|----|-----|------|
| 视频进度 | `/api/progress` | `client_updated_at` LWW |
| 收藏词 / 短语 | `/api/vocab` `/api/phrases` | 行级 upsert |
| 学习偏好 | `/api/preferences` | 全量覆盖 |
| FSRS 复习 | `/api/review-backup` | revision CAS；409 先拉再合 |
| 阅读书架+进度+词表 | `/api/reading-backup` | revision CAS；文档按 id 并集；进度取较新 `lastOpenedAt` |
| 完整词书 | `/api/wordbook-backup` | revision CAS；按 word 合并，`updatedAtMs` LWW，occurrences 并集 |
| 学习设置 | `/api/app-settings-backup` | revision CAS；保留本机 `cloudApiBaseUrl` / LAN 地址 |
| 学习模块 | `/api/learning-modules/{kind}/progress` | revision CAS |
| 导入课 | `/api/imports` `/api/courses` | 原有 restore |

轻量修订号：`GET /api/sync/status` → `{ review, reading, wordbook, appSettings, learningModules }`。

## 大文档

阅读备份上限 16MB。超限时客户端剥离最大文档的 `plainText`/`segments`，保留元数据 + `contentHash`；有 hash 时可走 shared OCR / 重导入恢复正文。

## 一期不做

- 导入视频/音频文件本体再上传（B 站/网盘原链重下）
- 主题与纯设备 UI
- 口语 `learning.db` 全量迁移
- Desk/PK 临时房间态
