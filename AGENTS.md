# 项目协作规则

用户已授权：每次完成修改并通过相关验证后，检查手机连接状态。如果存在已授权且在线的 Android 手机，自动构建与手机现有安装相同 applicationId 的 APK，使用覆盖安装保留应用数据，并自动提交、推送本次任务的改动到 GitHub，不重复询问。

- 当前正式包名为 `com.acquire.english`，**以后装机一律打 release 包**：`flutter build apk --release --flavor prod --no-pub`，避免安装 `.dev` 导致重复图标，也避免 debug 签与手机上的 upload 签冲突。
- Release 签名走 `apps/mobile/android/key.properties` → `keystore/acquireenglish-upload.jks`（gitignored）。缺 `key.properties` / upload jks 时构建应失败，勿静默回退到 debug 签或本机 `~/.android/debug.keystore`。
- `team-debug.keystore` 仅留作本地 debug 调试，**不再用于覆盖安装到已装正式包的手机**。
- 仅提交当前任务的改动，保留其他未完成改动，不提交密钥、缓存或生成文件。
- 多台设备且无法确定目标时再询问；未连接或未授权时说明原因，不声称安装成功。
- 安装或推送失败时继续排查并明确报告结果；不要强推远端或通过卸载清除用户数据。

## 音视频只走 OSS / API（禁止打进 APK）

- **禁止**把语音、视频文件打进 App（勿放入 `apps/mobile/assets` 或任何随 APK 发布的资源目录）。
- 主存储为阿里云 OSS（`OSS_*`）；ECS `{media_cache_dir}/{namespace}/` 可作迁移期缓存。经 `OSS_PUBLIC_BASE` 或 `/media/{namespace}/…` 与 `/api/content/media/*` 按需读取。
- 文本语料可按需下载缓存；若文章有配套朗读/视频，须先上传到 OSS/`reading` 等命名空间后再播放。详见 `docs/MEDIA_ECS.md`。
