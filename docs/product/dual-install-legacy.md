# 改版双安装：正式包 + 旧版对照

**上架不变：** 改版继续 `com.acquire.english` + **原 upload 签名**（平台已审过的同一应用）。  
**旧版对照才换：** `.legacy` 包名 + **新 legacy 签名**（仅本机并排，不上架）。

Android 同包名不能并排；只换签名也不够。

| 槽 | 图标 | applicationId | 签名 | 用途 |
|----|------|---------------|------|------|
| **上架/改版** | 爱快英语 | `com.acquire.english` | **原 upload** | 日常 / 商店更新 |
| **旧版对照** | 爱快英语·旧版 | `com.acquire.english.legacy` | **新 legacy** | 并排对比；数据独立 |

本机归档：`D:\AcquireEnglish\artifacts\dual-install\`（apk 不进 git）

```bash
# 改版 / 上架（原签名）
flutter build apk --release --flavor prod --no-pub

# 旧版对照（新签名，不上架）
flutter build apk --release --flavor legacy --no-pub
```

后悔改版：用归档的 `*-prod-pre-redesign-*.apk` 对正式包 `adb install -r`（仍是原签名），不必卸对照槽。

更新：Asia/Shanghai 2026-11-28。
