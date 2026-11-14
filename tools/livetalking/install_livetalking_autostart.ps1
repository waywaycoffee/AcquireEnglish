# Register login/startup persistence for LiveTalking (same pattern as LiveKit agent).
# Usage:
#   powershell -ExecutionPolicy Bypass -File tools/livetalking/install_livetalking_autostart.ps1
#   powershell -ExecutionPolicy Bypass -File tools/livetalking/install_livetalking_autostart.ps1 -Unregister
param(
  [string]$TaskName = "AcquireEnglish-LiveTalking",
  [switch]$Unregister
)

$ErrorActionPreference = "Stop"
$ScriptDir = $PSScriptRoot
$Runner = Join-Path $ScriptDir "run_livetalking_watchdog.ps1"
$RunOnce = Join-Path $ScriptDir "run_livetalking.ps1"
$Root = (Resolve-Path (Join-Path $ScriptDir "..\..\third_party\LiveTalking")).Path
$StartupDir = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\Startup"
$StartupCmd = Join-Path $StartupDir "AcquireEnglish-LiveTalking.cmd"

if ($Unregister) {
  Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
  if (Test-Path $StartupCmd) { Remove-Item $StartupCmd -Force }
  Write-Host "Unregistered: $TaskName (+ Startup shortcut if present)"
  exit 0
}

if (-not (Test-Path $RunOnce)) {
  Write-Error "Missing $RunOnce"
}

$registered = $false
try {
  $action = New-ScheduledTaskAction `
    -Execute "powershell.exe" `
    -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$Runner`"" `
    -WorkingDirectory $Root
  $triggerLogon = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
  $settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -RestartCount 3 `
    -RestartInterval (New-TimeSpan -Minutes 1) `
    -ExecutionTimeLimit ([TimeSpan]::Zero)
  $principal = New-ScheduledTaskPrincipal `
    -UserId $env:USERNAME `
    -LogonType Interactive `
    -RunLevel Limited

  Register-ScheduledTask `
    -TaskName $TaskName `
    -Action $action `
    -Trigger $triggerLogon `
    -Settings $settings `
    -Principal $principal `
    -Force | Out-Null
  $registered = $true
  Write-Host "Registered scheduled task: $TaskName (AtLogOn)"
} catch {
  Write-Host "Scheduled task registration skipped: $($_.Exception.Message)"
}

New-Item -ItemType Directory -Force -Path $StartupDir | Out-Null
@"
@echo off
start "" /min powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "$Runner"
"@ | Set-Content -Encoding ASCII $StartupCmd
Write-Host "Startup shortcut: $StartupCmd"
Write-Host "  Root:   $Root"
Write-Host "  Runner: $Runner"
if ($registered) {
  try { Start-ScheduledTask -TaskName $TaskName } catch {}
  Write-Host "Start now: Start-ScheduledTask -TaskName '$TaskName'"
}
Write-Host "Or manually: powershell -File `"$RunOnce`""
