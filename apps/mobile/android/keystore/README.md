# Android signing (AcquireEnglish)

## Release / Play upload

- `acquireenglish-upload.jks` + `../key.properties` (both gitignored)
- Used by `buildTypes.release` when `key.properties` exists

## Debug / sideload (shared team cert)

| File | Role |
|------|------|
| `team-debug.keystore` | Shared debug cert for all sideload machines |

- Alias: `androiddebugkey`
- Store / key password: `android`
- SHA-256: `2D:79:38:C4:63:EE:0A:E6:F9:52:CA:2D:97:9D:28:55:C7:2F:4F:4A:29:FA:43:7E:30:9F:A5:E7:94:30:44:57`

`app/build.gradle.kts` **requires** this file for debug builds (and for release when `key.properties` is absent). It does **not** fall back to `~/.android/debug.keystore`, so machines cannot accidentally ship mismatched signatures.

### Other computers

1. Copy `apps/mobile/android/keystore/team-debug.keystore` from a machine that already has it
2. Keep the path identical; do **not** commit (`*.keystore` is gitignored)
3. Rebuild: `flutter build apk --debug --flavor prod`

Then `adb install -r` overlays without `INSTALL_FAILED_UPDATE_INCOMPATIBLE`.
