# Android signing (AcquireEnglish)

Three certs — **do not mix** when overlay-installing the same `applicationId`.

| Cert | Package | Used for |
|------|---------|----------|
| `acquireenglish-upload.jks` | `com.acquire.english` | Website / prod release |
| `acquireenglish-legacy.jks` | `com.acquire.english.legacy` | Side-by-side **旧版对照** (dual-install) |
| `team-debug.keystore` | any + debug | Local debug sideload only |

Phone currently on website package → must build **prod** with **upload** cert to keep data.

## Dual-install (改版对照)

**上架 / 改版 = 原包名 + 原 upload 签名（不换，避免影响已审流程）。**  
**旧版对照 = 新包名 `.legacy` + 新 legacy 签名（仅本机并排，不上架）。**

| 图标名 | applicationId | 签名 | 命令 |
|--------|---------------|------|------|
| 爱快英语（上架/改版） | `com.acquire.english` | **原 upload** | `flutter build apk --release --flavor prod --no-pub` |
| 爱快英语·旧版（对照） | `com.acquire.english.legacy` | **新 legacy** | `flutter build apk --release --flavor legacy --no-pub` |

本地归档目录（不进 git）：`D:\AcquireEnglish\artifacts\dual-install\`

- `*-prod-release.apk` — 正式包快照（覆盖安装回退用）
- `*-legacy-release.apk` — 并排对照包（另签，不碰正式数据）

```powershell
adb install -r artifacts\dual-install\<prod>.apk          # 回退正式包
adb install    artifacts\dual-install\<legacy>.apk       # 并排装旧版对照
```

## Release / website (upload)

- Files (both gitignored):
  - `apps/mobile/android/keystore/acquireenglish-upload.jks`
  - `apps/mobile/android/key.properties`
- Alias: `acquireenglish`
- SHA-256: `2C:BE:5F:AB:FE:3C:22:18:35:A5:57:C2:E7:41:E9:AE:5F:78:F2:3E:BE:F2:A8:C3:BE:27:A1:9E:C4:4F:AB:C6`
- Used by `buildTypes.release` when `key.properties` exists

### Other computers (cover-install website APK)

1. Copy **both** `acquireenglish-upload.jks` and `../key.properties` from a machine that already has them
2. Build release (not debug):

```bash
cd apps/mobile
flutter build apk --release --flavor prod --no-pub \
  --target-platform android-arm64 \
  --dart-define-from-file=.env
```

3. `adb install -r` the release APK — fingerprint must stay `2C:BE:5F:AB…`

## Legacy compare (dual-install)

- Files (gitignored):
  - `apps/mobile/android/keystore/acquireenglish-legacy.jks`
  - `apps/mobile/android/key-legacy.properties`
- Alias: `acquireenglishlegacy`
- SHA-256: `51:7E:85:FA:80:C1:49:2B:75:18:CC:99:A8:18:54:FF:9E:D5:B8:58:C4:6A:F9:90:2C:62:49:44:82:B6:F2:45`
- Launcher label: **爱快英语·旧版**

```bash
cd apps/mobile
flutter build apk --release --flavor legacy --no-pub \
  --target-platform android-arm64
```

## Debug / sideload (shared team cert)

| File | Role |
|------|------|
| `team-debug.keystore` | Shared debug cert for all sideload machines |

- Alias: `androiddebugkey`
- Store / key password: `android`
- SHA-256: `2D:79:38:C4:63:EE:0A:E6:F9:52:CA:2D:97:9D:28:55:C7:2F:4F:4A:29:FA:43:7E:30:9F:A5:E7:94:30:44:57`

`app/build.gradle.kts` **requires** this file for debug builds. It does **not** fall back to `~/.android/debug.keystore`.

### Other computers (debug only)

1. Copy `apps/mobile/android/keystore/team-debug.keystore`
2. Rebuild: `flutter build apk --debug --flavor prod`
3. Only overlays devices that already have the **debug** cert (`2D:79…`), not the website release build
