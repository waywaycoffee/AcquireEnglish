# Android signing (AcquireEnglish)

## Release / Play upload

- `acquireenglish-upload.jks` + `../key.properties` (both gitignored)
- Used by `buildTypes.release` when `key.properties` exists

## Debug / sideload (Scheme A — shared cert)

**Master machine:** this developer Mac.

| File | Role |
|------|------|
| `team-debug.keystore` | Shared debug cert (copy of master `~/.android/debug.keystore`) |

`app/build.gradle.kts` signs **debug** builds with `team-debug.keystore` when present
(password/alias: standard Android debug `android` / `androiddebugkey`).

### Other computers

1. Copy from master Mac:
   `apps/mobile/android/keystore/team-debug.keystore`
2. Keep path identical; do **not** commit (gitignored `*.keystore`)
3. Rebuild: `flutter build apk --debug --flavor prod`

Then `adb install -r` overlays without `INSTALL_FAILED_UPDATE_INCOMPATIBLE`.

### Refresh master keystore

On the master Mac:

```bash
cp -f ~/.android/debug.keystore apps/mobile/android/keystore/team-debug.keystore
```

Re-copy to every other machine after refresh.
