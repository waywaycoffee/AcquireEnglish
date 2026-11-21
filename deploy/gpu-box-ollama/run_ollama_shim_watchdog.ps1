$ErrorActionPreference = 'Continue'
$env:OLLAMA_MODEL = 'qwen2.5:7b'
$env:OLLAMA_HOST = '0.0.0.0'
$env:OLLAMA_PORT = '11434'
$env:OLLAMA_MODEL_DIR = 'D:\AcquireEnglish\deploy\gpu-box-ollama\models'
$env:MODELSCOPE_MODEL = 'Qwen/Qwen2.5-7B-Instruct'
Set-Location 'D:\AcquireEnglish\deploy\gpu-box-ollama'
while ($true) {
  try {
    & 'D:\AcquireEnglish\third_party\LiveTalking\.venv\Scripts\python.exe' 'D:\AcquireEnglish\deploy\gpu-box-ollama\openai_compat_server.py' --host 0.0.0.0 --port 11434 --preload
  } catch { Write-Host $_ }
  Start-Sleep -Seconds 5
}
