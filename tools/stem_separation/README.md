# Stem separation helper (趣配音伴奏轨)

GPU 箱上运行，供 App 拉取 `no_vocals.wav`：

```bash
pip install -r requirements.txt
# optional: pip install demucs
uvicorn app:app --host 0.0.0.0 --port 8790
```

App 通过 `--dart-define=STEM_SEPARATION_URL=http://host:8790` 或后续设置项接入。
无 Demucs 时回退 ffmpeg 中置声道衰减。
