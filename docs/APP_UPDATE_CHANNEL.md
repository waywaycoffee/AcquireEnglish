# 官网 Android 更新通道

App 进入首页时会请求：

`GET https://acquireenglish.curlhairai.com/downloads/android-latest.json`

若 `version_code` / `version` 高于本机，弹出更新对话框；用户确认后下载 APK 并拉起系统安装器。设置页「检查更新」走同一清单。

## 发版时必做

1. `flutter build apk --release --flavor prod --no-pub --target-platform android-arm64`
2. 上传  
   `/opt/acquireenglish/www/downloads/AcquireEnglish-android-<ver>.apk`  
   并 `ln -sfn` 到 `AcquireEnglish-android-latest.apk`
3. 更新 `apps/web/public/downloads/android-latest.json`（version / version_code / sha256 / notes，必要时 force）并上传同路径
4. 更新 `apps/web/public/download.html` 版本号文案

## 清单字段

| 字段 | 说明 |
|------|------|
| `version` | 如 `0.2.260` |
| `version_code` | Android `versionCode`，优先比较 |
| `apk_url` | 建议指向 `…/AcquireEnglish-android-latest.apk` |
| `apk_name` | 本地下载文件名 |
| `sha256` | 可选；有则下载后校验 |
| `notes` | 弹窗说明 |
| `force` | `true` 时强制更新：无「稍后」、不可点遮罩关闭 |
| `min_version_code` | 本机 `versionCode` 低于该值时视为强制更新 |

## 行为说明

- 首页**每次进入都会检查**清单（不再「每天只查一次」，避免同日发版漏提示）。
- 普通更新：用户点「稍后」后，同一 `version` 本次安装周期内不再自动弹。
- 强制更新：忽略「稍后」记录；装完新包后按新 `version_code` 再比。

旧版若仍指向 GitHub Release，需先手动装一次本通道包后才会自动提示后续更新。当前已装的旧包若当天已做过静默检查，也不会弹出；请先官网下载一次带强制更新逻辑的包。
