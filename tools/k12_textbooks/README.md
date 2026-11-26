# K12 有声教材（本机人教版结构化入库）

本地扫 `docs/教材` 里的 **人教版 PDF + 同目录 MP3** → 打包上传 ECS  
`media/reading/k12/{book_id}/`（`book.pdf` + `audio/*.mp3` + `book.json`/`manifest.json`）。

点读（OCR→译→TTS）下一阶段；本阶段验证「整夹导入 + 课音频对应」。

## 本机目录（实际）

```text
docs/教材/小学/人教版（PEP）（主编：吴欣）/四年级/上册/2026年度/
  （…）英语 四年级上册.pdf
  01_Unit 1 Listen and chant.mp3
  03_Unit 1 A Let's talk.mp3
  …
```

多「年度」时默认只取**最新年**一册。

## 一键入库人教

```powershell
cd D:\AcquireEnglish

# 扫描可导入册
python tools/k12_textbooks/scan_local.py --pep-only --ready-only

# 预览
python tools/k12_textbooks/import_pep_local.py --dry-run

# 全部人教 ready 册上传 ECS（PDF+MP3）
python tools/k12_textbooks/import_pep_local.py

# 只导指定册
python tools/k12_textbooks/import_pep_local.py --book-id pep-y3-wuxin-g4-b --limit 1
```

## ECS 布局

```text
media/reading/k12/
  catalog.json
  {book_id}/
    book.pdf
    book.json          # 课次清单（API 用）
    manifest.json      # 同内容别名
    audio/u01_a_03.mp3
```

- API：`/api/reading/textbooks`、`/api/reading/textbooks/{book_id}`
- 音频 URL：`/media/reading/k12/{book_id}/audio/...`（不进 APK）

## 网盘三链（可选）

分享链配置见 [`sources.json`](sources.json)。若要从网盘补 PDF-only 清单，可用 `auto_seed_from_netdisk.py`；**本机人教有完整 MP3 时优先本脚本**。

## 注意

- `docs/教材/` 已 gitignore；版权教材走运营私有库，勿进公共分享池。
- 点读：页内点选 → OCR → 中译 → **TTS**（非 ASR）。
