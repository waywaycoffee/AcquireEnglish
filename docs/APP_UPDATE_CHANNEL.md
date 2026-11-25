# 官网 Android 更新通道

App 启动后（首页）每天最多静默检查一次：

`GET https://acquireenglish.curlhairai.com/downloads/android-latest.json`

若 `version_code` / `version` 高于本机，弹出「发现新版本」；用户确认后下载 APK 并拉起系统安装器。设置页「检查更新」走同一清单。

## 发版时必做

1. `flutter build apk --release --flavor prod --no-pub --target-platform android-arm64`
2. 上传  
   `/opt/acquireenglish/www/downloads/AcquireEnglish-android-<ver>.apk`  
   并 `ln -sfn` 到 `AcquireEnglish-android-latest.apk`
3. 更新 `apps/web/public/downloads/android-latest.json`（version / version_code / sha256 / notes）并上传同路径
4. 更新 `apps/web/public/download.html` 版本号文案

## 清单字段

| 字段 | 说明 |
|------|------|
| `version` | 如 `0.2.257` |
| `version_code` | Android `versionCode`，优先比较 |
| `apk_url` | 建议指向 `…/AcquireEnglish-android-latest.apk` |
| `apk_name` | 本地下载文件名 |
| `sha256` | 可选；有则下载后校验 |
| `notes` | 弹窗说明 |

旧版若仍指向 GitHub Release，需先手动装一次本通道包后才会自动提示后续更新。
