# AcquireEnglish 功能测试矩阵

一键跑通：`tools/smoke/run_feature_matrix.sh`

| ID | 功能 | 自动化入口 | 判定 |
|----|------|------------|------|
| F01 | 生产 LiveKit / 陪练管线默认地址 | `feature_acceptance_matrix_test` F01 | 默认 URL 正确；`caurlhairai` 可纠正 |
| F02 | 导入时检查并补齐中英字幕 | F02 + `subtitle_completion_enqueue_test` | 缺 EN/ZH/皆缺分别入队 |
| F03 | 字幕与语音不一致 → ASR 时间轴重建 | F03 + `asr_timeline_rebuild_test` | mismatch 检测 + rebuild |
| F04 | 口语陪练上下文契约 | F04 | VideoContext 字段完整 |
| F05 | 缺失侧检测 | F05 | 中文轨缺英文 / 双语齐全 |
| F06 | 短信登录 / 偏好 / Cookie 标记 | `services/api/tests/test_feature_matrix.py` + 生产冒烟 | token + `has_bilibili_cookie` |
| F07 | LiveKit token | API 本地 + 生产冒烟 | 返回 `url` + `token` |
| F08 | Coach session | 生产冒烟 `/coach/api/sessions` | 201 + session id |
| F09 | 健康检查 | 生产 `/api/health` `/coach/api/health` | status/ready |
| F10 | App 全量单元/组件 | `cd apps/mobile && flutter test` | All tests passed |

## 执行记录要求

1. Flutter：`cd apps/mobile && flutter test` → 全绿  
2. API：`cd services/api && pytest tests/test_feature_matrix.py tests/test_phone_wechat_auth.py -q` → 全绿  
3. 生产：脚本第 3 段，health / coach / sms / prefs / livekit / session → 全绿  
