# 碎片记忆 · 灵动岛 / 超级岛

用户主动开启的 **5 分钟** 单词碎片复习会话：轮换 FSRS 到期词，倒计时结束后自动收起。

## 产品行为

- 入口：每日复习页「碎片 5 分钟」；设置 →「碎片记忆灵动岛」开关。
- 摘要：当前词 + `mm:ss` 倒计时 + 已记数量。
- 展开/通知操作：认识 / 模糊 / 忘记（写入 FSRS）· 结束。
- 无操作时每 12 秒自动换下一张（**不写分**）。
- 结束原因：满 5 分钟、词耗尽、用户结束。

## Android（小米超级岛）

实现：[`MicroReviewIslandNotifier.kt`](../apps/mobile/android/app/src/main/kotlin/com/acquire/english/MicroReviewIslandNotifier.kt)

- 始终发送 ongoing 通知（非小米机降级可用）。
- HyperOS 通过 `notification.extras["miui.focus.param"]` 附加 `param_v2` + `param_island` + `timerInfo`。
- **正式上岛**需在小米开发者平台走场景审核（见下方清单）。无正式权限时通知仍可用，超级岛样式可能不生效。

### 提审材料清单

1. 企业开发者认证 + 开通「小米超级岛」服务，配置正式签名指纹。
2. 场景预审文案：

   > 用户在 App 内主动点击「碎片 5 分钟」后开始一场有限时长的单词复习。超级岛展示当前词与倒计时，支持认识/模糊/忘记快捷评分；倒计时结束或用户结束时通知自动关闭。非营销、非长期常驻。

3. 正式方案：开始 → 换词更新 → 评分 → 结束各节点效果图（可用设计稿 `micro-review-*.jpg`）。
4. 白名单真机联调（Xiaomi 14 等）→ 提交正式 APK 上线验证 → 灰度放量。

`business` 字段：`micro_review_session`。

## iOS（Dynamic Island / Live Activities）

- Dart：[`IosMicroReviewIslandBridge`](../apps/mobile/lib/features/micro_review/data/micro_review_island_bridge.dart) → MethodChannel `com.acquire.english/micro_review_live_activity`
- Runner：[`AppDelegate.swift`](../apps/mobile/ios/Runner/AppDelegate.swift) 已注册 channel（未接 Widget 前 `start` 返回 false，应用内卡片仍可用）
- Widget 源码目录：[`apps/mobile/ios/MicroReviewWidget/`](../apps/mobile/ios/MicroReviewWidget/)
- Runner `Info.plist` 已加 `NSSupportsLiveActivities` 与 URL Scheme `acquireenglish`

### Xcode 一次性接线（需 macOS）

1. 打开 `apps/mobile/ios/Runner.xcworkspace`
2. File → New → Target → Widget Extension，名称建议 `MicroReviewWidget`，Embed in Runner
3. 将本仓库 `ios/MicroReviewWidget/*.swift` 加入该 Target（替换模板文件）
4. Runner 与 Extension 均勾选 App Group：`group.com.acquire.english`
5. 在 `AppDelegate` 的 channel handler 中用 ActivityKit `Activity.request` / `update` / `end` 对接（读写 App Group UserDefaults，字段与 Dart payload 一致：`word` / `gloss` / `endsAtMs` / `ratedCount`）
6. Extension `Info.plist` 含 `NSSupportsLiveActivities=true`
7. 真机 iOS 16.1+ 验证 Compact / Expanded / Lock Screen

评分按钮通过 `acquireenglish://micro-review?action=know|fuzzy|forget|end` 回主 App。

## 代码入口

| 模块 | 路径 |
|------|------|
| 会话状态机 | `lib/features/micro_review/domain/micro_review_session.dart` |
| 控制器 | `lib/features/micro_review/presentation/micro_review_controller.dart` |
| 平台桥 | `lib/features/micro_review/data/micro_review_island_bridge.dart` |
| 复习页按钮 | `daily_review_screen.dart` →「碎片 5 分钟」 |
