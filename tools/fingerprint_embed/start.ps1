# Start fingerprint embed service on RTX 5060 Ti (default :8092).
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $Root

# Reuse LiveTalking CUDA torch (5060 Ti). Nested venv --system-site-packages does NOT inherit parent venv packages.
$Py = "D:\AcquireEnglish\third_party\LiveTalking\.venv\Scripts\python.exe"
if (-not (Test-Path $Py)) { throw "LiveTalking CUDA python not found: $Py" }

$env:FINGERPRINT_EMBED_HOST = if ($env:FINGERPRINT_EMBED_HOST) { $env:FINGERPRINT_EMBED_HOST } else { "0.0.0.0" }
$env:FINGERPRINT_EMBED_PORT = if ($env:FINGERPRINT_EMBED_PORT) { $env:FINGERPRINT_EMBED_PORT } else { "8092" }
$env:FINGERPRINT_EMBED_MODEL = if ($env:FINGERPRINT_EMBED_MODEL) { $env:FINGERPRINT_EMBED_MODEL } else { "BAAI/bge-small-zh-v1.5" }
# China-friendly Hugging Face mirror (first download only).
if (-not $env:HF_ENDPOINT) { $env:HF_ENDPOINT = "https://hf-mirror.com" }

Write-Host "Starting fingerprint embed on $($env:FINGERPRINT_EMBED_HOST):$($env:FINGERPRINT_EMBED_PORT) model=$($env:FINGERPRINT_EMBED_MODEL)"
& $Py -m uvicorn app:app --host $env:FINGERPRINT_EMBED_HOST --port $env:FINGERPRINT_EMBED_PORT
