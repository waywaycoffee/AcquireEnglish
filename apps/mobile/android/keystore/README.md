# Android signing (AcquireEnglish)

Two different certs — **do not mix** when overlay-installing.

| Cert | SHA-256 prefix | Used for |
|------|----------------|----------|
| `acquireenglish-upload.jks` | **`2C:BE:5F:AB…`** | Website / release APK (`0.2.253` etc.) |
| `team-debug.keystore` | **`2D:79:38:C4…`** | Local debug sideload only |

Phone currently on website package → must build with **upload** cert to keep data.

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

## Debug / sideload (shared team cert)

| File | Role |
|------|------|
| `team-debug.keystore` | Shared debug cert for all sideload machines |

- Alias: `androiddebugkey`
- Store / key password: `android`
- SHA-256: `2D:79:38:C4:63:EE:0A:E6:F9:52:CA:2D:97:9D:28:55:C7:2F:4F:4A:29:FA:43:7E:30:9F:A5:E7:94:30:44:57`

`app/build.gradle.kts` **requires** this file for debug builds (and for release when `key.properties` is absent). It does **not** fall back to `~/.android/debug.keystore`.

### Other computers (debug only)

1. Copy `apps/mobile/android/keystore/team-debug.keystore`
2. Rebuild: `flutter build apk --debug --flavor prod`
3. Only overlays devices that already have the **debug** cert (`2D:79…`), not the website release build
