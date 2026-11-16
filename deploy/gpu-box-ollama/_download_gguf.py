from modelscope import snapshot_download
import os
cache = r"D:\AcquireEnglish\deploy\gpu-box-ollama\models"
print("downloading Qwen2.5-7B-Instruct-GGUF Q4_K_M ...", flush=True)
path = snapshot_download(
    "Qwen/Qwen2.5-7B-Instruct-GGUF",
    cache_dir=cache,
    allow_patterns=["*q4_k_m*"],
)
print("DONE", path, flush=True)
