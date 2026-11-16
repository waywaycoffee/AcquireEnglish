# Poll LiveTalking admin sessions and restart when slots are full / stale.
# Run on the GPU Windows box (5060ti), optionally from Task Scheduler every 2 min:
#   powershell -ExecutionPolicy Bypass -File tools/livetalking/cleanup_livetalking_sessions.ps1
$ErrorActionPreference = "Continue"
$AdminUrl = if ($env:LIVETALKING_ADMIN_URL) { $env:LIVETALKING_ADMIN_URL } else { "http://127.0.0.1:8010/api/admin/sessions" }
$ConfigUrl = if ($env:LIVETALKING_CONFIG_URL) { $env:LIVETALKING_CONFIG_URL } else { "http://127.0.0.1:8010/api/admin/config" }
$Restart = Join-Path $PSScriptRoot "restart_livetalking.ps1"
$StaleMinutes = if ($env:LIVETALKING_STALE_MINUTES) { [int]$env:LIVETALKING_STALE_MINUTES } else { 8 }

function Get-Json($url) {
  try {
    return Invoke-RestMethod -Uri $url -TimeoutSec 4 -Method Get
  } catch {
    Write-Host ("[{0}] admin probe failed: {1}" -f (Get-Date -Format o), $_)
    return $null
  }
}

$config = Get-Json $ConfigUrl
$sessions = Get-Json $AdminUrl
if ($null -eq $sessions) {
  Write-Host "LiveTalking admin unreachable — skipping."
  exit 0
}

$max = 5
if ($config -and $config.max_session) {
  $max = [int]$config.max_session
}

# Upstream may return {sessions:[...]} or a bare list.
$list = @()
if ($sessions -is [System.Array]) {
  $list = @($sessions)
} elseif ($sessions.sessions) {
  $list = @($sessions.sessions)
} elseif ($sessions.data) {
  $list = @($sessions.data)
} elseif ($sessions.count -ne $null -and $sessions.sessions -eq $null) {
  # {count:N} only
  $count = [int]$sessions.count
  Write-Host ("[{0}] sessions={1}/{2}" -f (Get-Date -Format o), $count, $max)
  if ($count -ge $max) {
    Write-Host "Session slots full — restarting LiveTalking to clear zombies."
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Restart
  }
  exit 0
}

$count = $list.Count
Write-Host ("[{0}] sessions={1}/{2}" -f (Get-Date -Format o), $count, $max)

$now = Get-Date
$stale = 0
foreach ($row in $list) {
  $created = $null
  foreach ($key in @("created_at", "createdAt", "start_time", "startTime", "timestamp")) {
    if ($row.$key) {
      try { $created = [DateTime]$row.$key } catch { $created = $null }
      if ($created) { break }
    }
  }
  if ($created -and (($now - $created).TotalMinutes -ge $StaleMinutes)) {
    $stale += 1
  }
}

$needRestart = $false
if ($count -ge $max) {
  Write-Host "Session slots full ($count/$max)."
  $needRestart = $true
} elseif ($stale -gt 0 -and $stale -eq $count) {
  Write-Host "All $stale sessions look stale (>= ${StaleMinutes}m)."
  $needRestart = $true
}

if ($needRestart) {
  Write-Host "Restarting LiveTalking to reclaim GPU session slots..."
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Restart
  Start-Sleep -Seconds 4
  $after = Get-Json $AdminUrl
  Write-Host ("After restart probe: {0}" -f ($after | ConvertTo-Json -Compress))
} else {
  Write-Host "Sessions healthy — no restart."
}
