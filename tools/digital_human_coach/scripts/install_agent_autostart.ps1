# Register a persistent scheduled task that keeps acquire-oral-coach alive across reboot.
# Usage:
#   powershell -ExecutionPolicy Bypass -File tools/digital_human_coach/scripts/install_agent_autostart.ps1
# Optional:
#   -TaskName AcquireEnglish-LiveKit-Agent
#   -Unregister
param(
  [string]$TaskName = "AcquireEnglish-LiveKit-Agent",
  [switch]$Unregister
)

$ErrorActionPreference = "Stop"
$Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$Runner = Join-Path $PSScriptRoot "run_agent_watchdog.ps1"
$RunAgent = Join-Path $PSScriptRoot "run_agent.ps1"
$StartupDir = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\Startup"
$StartupCmd = Join-Path $StartupDir "AcquireEnglish-LiveKit-Agent.cmd"

if ($Unregister) {
  Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
  if (Test-Path $StartupCmd) { Remove-Item $StartupCmd -Force }
  Write-Host "Unregistered: $TaskName (+ Startup shortcut if present)"
  exit 0
}

if (-not (Test-Path $RunAgent)) {
  Write-Error "Missing $RunAgent"
}

# Watchdog: restart agent if the python process exits.
@"
`$ErrorActionPreference = 'Continue'
`$Root = '$Root'
`$RunAgent = '$RunAgent'
Set-Location `$Root
while (`$true) {
  try {
    Write-Host ("[{0}] starting acquire-oral-coach agent" -f (Get-Date -Format o))
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File `$RunAgent
  } catch {
    Write-Host ("[{0}] agent crashed: {1}" -f (Get-Date -Format o), `$_)
  }
  Start-Sleep -Seconds 5
}
"@ | Set-Content -Encoding UTF8 $Runner

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

# Always drop a Startup .cmd so reboot persistence works without admin elevation.
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
Write-Host "Or manually: powershell -File `"$RunAgent`""
