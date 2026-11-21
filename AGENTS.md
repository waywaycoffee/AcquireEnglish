# 项目协作规则

用户已授权：每次完成修改并通过相关验证后，检查手机连接状态。如果存在已授权且在线的 Android 手机，自动构建与手机现有安装相同 applicationId 的 APK，使用覆盖安装保留应用数据，并自动提交、推送本次任务的改动到 GitHub，不重复询问。

- 当前正式包名为 `com.acquire.english`，构建使用 `flutter build apk --debug --flavor prod --no-pub`，避免安装 `.dev` 导致重复图标。
- 仅提交当前任务的改动，保留其他未完成改动，不提交密钥、缓存或生成文件。
- 多台设备且无法确定目标时再询问；未连接或未授权时说明原因，不声称安装成功。
- 安装或推送失败时继续排查并明确报告结果；不要强推远端或通过卸载清除用户数据。

## 音视频只走 ECS

- **禁止**把语音、视频文件打进 App（勿放入 `apps/mobile/assets` 或任何随 APK 发布的资源目录）。
- 所有语音/视频保存在 ECS（API 机）`{media_cache_dir}/{namespace}/`，经 `/media/{namespace}/…` 与 `/api/content/media/*`（或 foundation 兼容接口）按需读取。
- 文本语料可按需下载缓存；若文章有配套朗读/视频，须先上传到 ECS 的 `reading` 等命名空间后再播放。详见 `docs/MEDIA_ECS.md`。

## 音视频只走 ECS

- **禁止**把语音、视频文件打进 App（勿放入 `apps/mobile/assets` 或任何随 APK 发布的资源目录）。
- 所有语音/视频保存在 ECS（API 机）`{media_cache_dir}/{namespace}/`，经 `/media/{namespace}/…` 与 `/api/content/media/*`（或 foundation 兼容接口）按需读取。
- 文本语料可按需下载缓存；若文章有配套朗读/视频，须先上传到 ECS 的 `reading` 等命名空间后再播放。详见 `docs/MEDIA_ECS.md`。
