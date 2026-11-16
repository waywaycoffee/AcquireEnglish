from modelscope import snapshot_download
import os
cache = r"D:\AcquireEnglish\deploy\gpu-box-ollama\models"
print("download Qwen2.5-7B-Instruct ...", flush=True)
path = snapshot_download("Qwen/Qwen2.5-7B-Instruct", cache_dir=cache)
print("DONE", path, flush=True)
