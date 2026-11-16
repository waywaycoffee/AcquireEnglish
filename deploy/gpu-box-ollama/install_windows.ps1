# Windows 5060 Ti: local qwen2.5:7b for EN→ZH (OpenAI-compatible :11434).
# Uses LiveTalking CUDA venv + ModelScope + transformers 4-bit (no Ollama installer).
#
#   powershell -ExecutionPolicy Bypass -File .\install_windows.ps1
param(
  [string]$ModelId = "qwen2.5:3b",
  [string]$ListenHost = "0.0.0.0",
  [int]$Port = 11434,
  [switch]$SkipDownload,
  [switch]$Unregister
)

$ErrorActionPreference = "Stop"
$Root = $PSScriptRoot
$VenvPy = (Resolve-Path (Join-Path $Root "..\..\third_party\LiveTalking\.venv\Scripts\python.exe")).Path
$VenvPip = (Resolve-Path (Join-Path $Root "..\..\third_party\LiveTalking\.venv\Scripts\pip.exe")).Path
$Server = Join-Path $Root "openai_compat_server.py"
$Watchdog = Join-Path $Root "run_ollama_shim_watchdog.ps1"
$ModelDir = Join-Path $Root "models"
$TaskName = "AcquireEnglish-Ollama-Qwen"
$StartupDir = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\Startup"
$StartupCmd = Join-Path $StartupDir "AcquireEnglish-Ollama-Qwen.cmd"

if ($Unregister) {
  Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
  if (Test-Path $StartupCmd) { Remove-Item $StartupCmd -Force }
  Write-Host "Unregistered $TaskName"
  exit 0
}

Write-Host "==> pip deps (Tsinghua)"
& $VenvPip install -i https://pypi.tuna.tsinghua.edu.cn/simple --trusted-host pypi.tuna.tsinghua.edu.cn `
  fastapi "uvicorn[standard]" modelscope bitsandbytes accelerate "transformers>=4.51" | Out-Host

New-Item -ItemType Directory -Force -Path $ModelDir | Out-Null
if (-not $SkipDownload) {
  Write-Host "==> ModelScope pull Qwen/Qwen2.5-3B-Instruct (~6GB first time)"
  $dl = @"
from modelscope import snapshot_download
print(snapshot_download('Qwen/Qwen2.5-3B-Instruct', cache_dir=r'$ModelDir'))
"@
  $tmp = Join-Path $Root "_download_instruct.py"
  Set-Content -Path $tmp -Value $dl -Encoding UTF8
  & $VenvPy $tmp
}

@"
`$ErrorActionPreference = 'Continue'
`$env:OLLAMA_MODEL = '$ModelId'
`$env:OLLAMA_HOST = '$ListenHost'
`$env:OLLAMA_PORT = '$Port'
`$env:OLLAMA_MODEL_DIR = '$ModelDir'
`$env:MODELSCOPE_MODEL = 'Qwen/Qwen2.5-3B-Instruct'
`$Py = '$VenvPy'
`$Server = '$Server'
Set-Location '$Root'
while (`$true) {
  try {
    Write-Host ("[{0}] starting Qwen OpenAI shim :{1}" -f (Get-Date -Format o), '$Port')
    & `$Py `$Server --host `$env:OLLAMA_HOST --port `$env:OLLAMA_PORT --preload
  } catch {
    Write-Host ("[{0}] crashed: {1}" -f (Get-Date -Format o), `$_)
  }
  Start-Sleep -Seconds 5
}
"@ | Set-Content -Encoding UTF8 $Watchdog

$registered = $false
try {
  $action = New-ScheduledTaskAction -Execute "powershell.exe" `
    -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$Watchdog`"" `
    -WorkingDirectory $Root
  $trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
  $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -StartWhenAvailable -ExecutionTimeLimit ([TimeSpan]::Zero)
  $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited
  Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger `
    -Settings $settings -Principal $principal -Force | Out-Null
  $registered = $true
  Write-Host "Registered: $TaskName"
} catch {
  Write-Host "Scheduled task skipped: $($_.Exception.Message)"
}

New-Item -ItemType Directory -Force -Path $StartupDir | Out-Null
@"
@echo off
start "" /min powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "$Watchdog"
"@ | Set-Content -Encoding ASCII $StartupCmd
Write-Host "Startup: $StartupCmd"

if ($registered) {
  try { Start-ScheduledTask -TaskName $TaskName } catch {}
} else {
  Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$Watchdog`"" -WindowStyle Minimized
}

Write-Host ""
Write-Host "App → 翻译来源=本地 Ollama"
Write-Host "  Base URL = http://100.115.252.55:${Port}/v1"
Write-Host "  Model    = $ModelId"
Write-Host "Verify: powershell -File .\verify_windows.ps1"
