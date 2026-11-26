# K12 有声教材本地导入（PDF + 同目录 MP3）

本机挑好课本文件夹 → 打包 → 上传 ECS `reading/textbooks/`。  
App **K12 英语教材书架** 对已上传册次显示「有声教材」，点课播放配套 MP3，可打开 PDF。

> 不走百度网盘全量镜像；只上传你本地点选的册次，控制服务器体积。

## 目录约定

每个册次一个文件夹，PDF 与 MP3 同级：

```text
…/北京版/四年级/下册/
  （…）义务教育教科书·英语 四年级下册.pdf
  01_Unit One_Lesson 1  What's Your Hobby.mp3
  05_Unit One_Letters and Sounds sh.mp3
  …
```

文件名：`序号_单元_课次或类型 标题.mp3`。

## 样例：北京版四年级下册

```powershell
cd D:\AcquireEnglish
python tools/k12_textbooks/test_parse_audio.py
python tools/k12_textbooks/import_beijing_g4_b.py --keep-package D:\AcquireEnglish\tmp\k12-textbook-beijing-g4-b
```

ECS 落盘：

```text
/opt/acquireenglish/services/api/media/reading/textbooks/
  catalog.json
  beijing-g4-b/
    book.json
    book.pdf
    audio/01.mp3 … 37.mp3
```

验证：

```text
https://acquireenglish.curlhairai.com/api/reading/textbooks
https://acquireenglish.curlhairai.com/api/reading/textbooks/beijing-g4-b
```

## 通用导入（下一册复用）

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
  --volume 下册 `
  --keep-package D:\AcquireEnglish\tmp\k12-out
```

只打包不上传：加 `--skip-upload`。  
已有 package 再传：`python tools/k12_textbooks/upload_to_ecs.py --package D:\path\to\beijing-g4-b`

## 注意

- `docs/教材/` 已 gitignore，勿把 PDF/MP3 提交进仓库或打进 APK。
- 版权教材仅供有授权学习使用，不进入公共指纹池。
- 点读（OCR→翻译→TTS）在有声书架稳定后再做。
