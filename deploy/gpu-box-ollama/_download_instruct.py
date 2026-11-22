from modelscope import snapshot_download

cache = r"D:\AcquireEnglish\deploy\gpu-box-ollama\models"
print("download Qwen2.5-3B-Instruct ...", flush=True)
path = snapshot_download("Qwen/Qwen2.5-3B-Instruct", cache_dir=cache)
print(path, flush=True)
