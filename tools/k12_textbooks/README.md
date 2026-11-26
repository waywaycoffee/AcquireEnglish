# K12 有声教材本地导入（PDF + 同目录 MP3）

流程：**扫描本机 `docs/教材` → 挑热门英语册次 → 打包上传 ECS**。  
不走百度网盘扫描；只上传本地点选的册次，控制服务器体积。

## 1. 扫描本地目录

默认根目录：`docs/教材/{小学|初中|高中}/英语/{版本}/{年级}/{上册|下册}/`

```powershell
cd D:\AcquireEnglish

# 全部英语候选
python tools/k12_textbooks/scan_local.py

# 只看热门版本（人教 PEP / 外研 / 译林 / 北京版 / 北师大 / 冀教…）
python tools/k12_textbooks/scan_local.py --hot-only --ready-only

# 写出 JSON，并打印可直接复制的导入命令
python tools/k12_textbooks/scan_local.py --hot-only --ready-only --print-import `
  --json tmp/k12-local-candidates.json
```

## 2. 导入某一册

### 样例：北京版四年级下册

```powershell
python tools/k12_textbooks/import_beijing_g4_b.py
```

### 通用

```powershell
python tools/k12_textbooks/import_book.py `
  --source "D:\AcquireEnglish\docs\教材\小学\英语\北京版\四年级\下册" `
  --book-id beijing-g4-b `
  --catalog-id "k12-textbook:beijing:k12_g4:b" `
  --title "English · Grade 4 Book 2" `
  --title-zh "英语 四年级 下册" `
  --edition 北京版 `
  --publisher 北京出版社 `
  --grade-id k12_g4 `
  --stage primary `
  --volume 下册
```

也可直接复制 `scan_local.py --print-import` 打出来的命令。

## 目录约定

每个册次文件夹内：课本 PDF 与配套 MP3 同级。

```text
…/北京版/四年级/下册/
  （…）义务教育教科书·英语 四年级下册.pdf
  01_Unit One_Lesson 1  What's Your Hobby.mp3
  …
```

若有多个 PDF，工具会优先选文件名含「英语 / 义务教育教科书」的那本。

## ECS 与 App

```text
/opt/acquireenglish/services/api/media/reading/textbooks/
  catalog.json
  beijing-g4-b/book.pdf|book.json|audio/*.mp3
```

- API：`/api/reading/textbooks`、`/api/reading/textbooks/{book_id}`
- App：K12 英语教材书架 → 已上传册次显示「有声教材」

## 注意

- `docs/教材/` 已 gitignore，勿提交 PDF/MP3，勿打进 APK。
- 版权教材仅供有授权学习使用。
- 点读（OCR→翻译→TTS）在有声书架稳定后再做。
