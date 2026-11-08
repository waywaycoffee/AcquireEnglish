# Flutter 移动端底座

已拉取到 `apps/mobile`（源自 [TideSparrow/shadowing-english](https://github.com/TideSparrow/shadowing-english)，MIT）。

品牌已改为 **AcquireEnglish**（`com.acquire.english`）。嵌套 `.git` 已移除，由仓库根目录统一管理。

```powershell
cd D:\AcquireEnglish\apps\mobile
$env:Path = "C:\src\flutter\bin;" + $env:Path
flutter pub get
flutter run --flavor prod
```

若目录损坏需重新拉取：

```powershell
cd D:\AcquireEnglish
Remove-Item -Recurse -Force apps\mobile -ErrorAction SilentlyContinue
git clone --depth 1 https://github.com/TideSparrow/shadowing-english.git apps\mobile
# 然后重新做品牌替换 / 或从本仓库恢复改动
```
