# Force-restart LiveTalking to clear zombie WebRTC sessions (5/5 full).
# Run on the GPU Windows box (5060ti):
#   powershell -ExecutionPolicy Bypass -File tools/livetalking/restart_livetalking.ps1
$ErrorActionPreference = "Continue"
$Root = (Resolve-Path (Join-Path $PSScriptRoot "..\..\third_party\LiveTalking")).Path
$Run = Join-Path $PSScriptRoot "run_livetalking.ps1"

Write-Host "Stopping LiveTalking python processes under $Root ..."
Get-CimInstance Win32_Process -Filter "Name = 'python.exe' OR Name = 'pythonw.exe'" |
  Where-Object { $_.CommandLine -match 'app\.py' -and $_.CommandLine -match 'webrtc' } |
  ForEach-Object {
    Write-Host ("  kill pid={0}" -f $_.ProcessId)
    Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
  }

Start-Sleep -Seconds 2
Write-Host "Starting LiveTalking..."
Start-Process -FilePath "powershell.exe" -ArgumentList @(
  "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $Run
) -WorkingDirectory $Root -WindowStyle Minimized
Write-Host "Done. Probe: http://127.0.0.1:8010/api/admin/sessions"
