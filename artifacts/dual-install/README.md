# Dual-install APK archive（本机对照包）

**上架策略（已定）：改版继续用原包名 + 原 upload 签名，不影响已过审上架流程；旧版对照才用新签名 + `.legacy` 包名。**

| 槽 | 文件 | applicationId | 签名 | 安装 |
|----|------|---------------|------|------|
| **上架/改版** | `*-prod-*.apk` | `com.acquire.english`（不变） | **原 upload** | `adb install -r` |
| **旧版对照** | `*-legacy-*.apk` | `com.acquire.english.legacy` | **新 legacy** | `adb install`（并排） |

桌面图标：

- **爱快英语** = 正式 / 改版（原签名，上架同一应用）
- **爱快英语·旧版** = 对照槽（新签名，仅本机对比，不上架）

本目录 `*.apk` 被 `.gitignore` 忽略，只留在本机 `D:\AcquireEnglish\artifacts\dual-install\`。
