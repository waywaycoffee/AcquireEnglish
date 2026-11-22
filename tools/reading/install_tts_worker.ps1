# Register + start reading TTS worker on 5060 Ti (queue from ECS, CosyVoice via
# local DASHSCOPE_API_KEY or ECS RPC). CosyVoice is cloud API — no local weights.
#
#   powershell -ExecutionPolicy Bypass -File .\tools\reading\install_tts_worker.ps1
param(
  [switch]$Unregister
)

$ErrorActionPreference = "Stop"
$Root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$Worker = Join-Path $Root "tools\reading\tts_worker.py"
$TaskName = "AcquireEnglish-Reading-TTS-Worker"
$PyCandidates = @(
  (Join-Path $Root "third_party\LiveTalking\.venv\Scripts\python.exe"),
  (Join-Path $Root "tools\subtitle\.venv\Scripts\python.exe"),
  "python"
)
$Py = $null
foreach ($c in $PyCandidates) {
  if ($c -eq "python" -or (Test-Path $c)) { $Py = $c; break }
}
if (-not $Py) { throw "No Python found for TTS worker" }

if ($Unregister) {
  Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
  Write-Host "Unregistered $TaskName"
  exit 0
}

if (-not (Test-Path $Worker)) { throw "Missing $Worker" }

# Ensure dashscope is importable when a local key is set (optional).
try {
  & $Py -c "import dashscope; print('dashscope-ok')"
} catch {
  Write-Host "dashscope not in this Python; worker will synthesize via ECS RPC."
}

$StartupDir = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\Startup"
$StartupCmd = Join-Path $StartupDir "AcquireEnglish-Reading-TTS-Worker.cmd"
New-Item -ItemType Directory -Force -Path $StartupDir | Out-Null
@"
@echo off
cd /d "$Root"
start "" /min "$Py" "$Worker"
"@ | Set-Content -Encoding ASCII $StartupCmd

$registered = $false
try {
  $action = New-ScheduledTaskAction -Execute $Py -Argument "`"$Worker`"" -WorkingDirectory $Root
  $trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
  $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -StartWhenAvailable -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
  $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited
  Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger `
    -Settings $settings -Principal $principal -Force | Out-Null
  Start-ScheduledTask -TaskName $TaskName
  $registered = $true
  Write-Host "Registered + started: $TaskName"
} catch {
  Write-Host "Scheduled task skipped ($($_.Exception.Message)); using Startup folder + foreground start."
}

# Always ensure a live process now.
$existing = Get-CimInstance Win32_Process -Filter "Name='python.exe'" |
  Where-Object { $_.CommandLine -match 'tts_worker\.py' }
if (-not $existing) {
  Start-Process -FilePath $Py -ArgumentList "`"$Worker`"" -WorkingDirectory $Root -WindowStyle Minimized
  Write-Host "Started TTS worker process"
}
Write-Host "Startup shortcut: $StartupCmd"
Write-Host "Worker claims ECS reading TTS jobs; audio lands under media/reading/tts/"
Write-Host "Optional: set user/machine DASHSCOPE_API_KEY for local CosyVoice synth."
