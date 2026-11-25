# 鸿蒙移植工作区

本目录使用 Flutter-OH 的原生 `FlutterAbility` 宿主，共用 `../mobile/lib`、`assets`、`third_party`。它不是 Android APK 包装器。2026-11-26 已完成无签名 Debug HAP 原生编译；尚未完成签名与真机验收，不是可上架的完整版本。

## 已建立

- 原生宿主位于 `ohos/`，bundleName 为 `com.acquire.english`，版本从 mobile 的 pubspec 同步。
- 鸿蒙依赖配置由 `tools/harmony/prepare_workspace.py` 生成，原 mobile pubspec 不变。
- path_provider、shared_preferences、file_selector、image_picker、camera、record、flutter_tts、package_info_plus、device_info_plus、url_launcher 使用 CPF-Flutter 鸿蒙实现，源提交固定在 `tools/harmony/plugins.json`。依赖解析和原生编译已通过，真机行为仍需验证。
- 官方 Flutter-OH 3.44.9 使用 Dart 3.12.2；鸿蒙构建配置排除不会参与 HAP 运行的代码生成器型 dev dependencies，把 record / LiveKit 共用的稳定 UUID API 统一到 4.5.3，并固定 Flutter 3.44 兼容的 Riverpod 与 Hive Flutter 包，不修改 Android/iOS 的依赖配置。生成代码仍由主工程维护。
- fluwx 当前上游版本已声明 OHOS 实现，待华为应用配置与真机验证。
- 麦克风及相机声明为使用期间申请，附用途说明。音视频必须从 ECS 按需获取，不加入资源包。

## 环境与执行

本机验证环境为 DevEco Studio 26.0.1 Mac ARM、HarmonyOS SDK API 26、OHPM 26.0.1.220。不要用 Android 的 keystore 代替鸿蒙签名证书。

Flutter-OH 安装目录默认为 `~/Library/Developer/AcquireEnglish/flutter-ohos`，固定版本为 `3.44.9+ohos-1.0.0`。`tools/harmony/flutterw` 仅为当前命令配置 DevEco、Node、ohpm、hvigor 与独立 Pub 缓存，不修改全局 Flutter。

DevEco CLI 安装在 `~/Library/Developer/AcquireEnglish/deveco-cli`，当前版本为 `1.3.0-stable`；启动脚本会把它加入当前命令的 PATH。依赖与引擎默认使用 Flutter 中国镜像，可通过已有环境变量覆盖。

```bash
python3 tools/harmony/prepare_workspace.py
python3 tools/harmony/check_workspace.py --require-toolchain
cd apps/mobile_harmony
../../tools/harmony/flutterw doctor -v
../../tools/harmony/flutterw pub get
../../tools/harmony/flutterw analyze
../../tools/harmony/flutterw build hap --debug --no-codesign
```

首次 Flutter-OH 安装需要下载 Dart/Engine 组件；网络中断时需恢复完成，不能将源码目录存在当成 SDK 已安装成功。可用 `FLUTTER_OHOS_HOME`、`DEVECO_HOME`、`HARMONY_PUB_CACHE` 覆盖本机路径。

Hvigor 不允许项目绝对路径包含中文。当前仓库路径含“程序”，因此本机验证在 `~/Library/Developer/AcquireEnglish/harmony-build-worktree` 的 Git worktree 中执行；CI 或其他机器也应使用纯 ASCII 路径。

宿主源文件通过上游模板创建。`create_host.py` 不覆盖已经存在的宿主，避免覆盖本机签名。宿主源码检查可独立运行：`python3 tools/harmony/check_workspace.py`。本机验证产物为 `build/ohos/hap/entry-default-unsigned.hap`，SHA-256 为 `61e5559ba5ae0bbce0bd47db47b60ad6064b2bdda8797129000e9c7e5f856a95`；构建产物不提交 Git。

## 仍需完成的适配

- media_kit / media_kit_video 的鸿蒙播放器实现及音视频网络播放。
- flutter_webrtc / livekit_client 版本兼容、音频会话与双工对话。
- SQLite 原生库装载、OCR 替换、后台任务、通知和悬浮窗的鸿蒙实现或明确的产品降级。
- record 与 flutter_tts 已配置鸿蒙 fork，需验证 API 差异、权限申请、音频输出和 ECS 朗读优先策略。
- 摄像头、照片选择、分享及用户数据恢复的真机验证。

公开发布前须在华为后台配置 bundleName / AppIdentifier / 签名，完成真实登录和支付测试。私钥、证书密码、Profile 只放在忽略的 `ohos/signing/` 或本机配置中；DevEco 生成的签名字段不得提交到 Git。
