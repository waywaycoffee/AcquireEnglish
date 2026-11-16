# Start real LiveTalking (lipku) WebRTC GPU server on 0.0.0.0:8010.
# Usage:
#   powershell -ExecutionPolicy Bypass -File tools/livetalking/run_livetalking.ps1
$ErrorActionPreference = "Stop"
$Root = (Resolve-Path (Join-Path $PSScriptRoot "..\..\third_party\LiveTalking")).Path
Set-Location $Root

$VenvPython = Join-Path $Root ".venv\Scripts\python.exe"
if (-not (Test-Path $VenvPython)) {
  Write-Error "Missing venv at $VenvPython — create with Python 3.12 and install torch + requirements.txt."
}

$model = Join-Path $Root "models\wav2lip.pth"
if (-not (Test-Path $model) -or (Get-Item $model).Length -lt 1MB) {
  Write-Error "Missing models\wav2lip.pth — download wav2lip256.pth (rename) or HF shibing624/ai-avatar-wav2lip."
}

# Prefer official avatar id; fall back to HF glass_man pack.
$avatarId = $env:LIVETALKING_AVATAR_ID
if ([string]::IsNullOrWhiteSpace($avatarId)) {
  if (Test-Path (Join-Path $Root "data\avatars\wav2lip256_avatar1")) {
    $avatarId = "wav2lip256_avatar1"
  } elseif (Test-Path (Join-Path $Root "data\avatars\wav2lip_avatar_glass_man")) {
    $avatarId = "wav2lip_avatar_glass_man"
  } else {
    $dirs = Get-ChildItem (Join-Path $Root "data\avatars") -Directory -ErrorAction SilentlyContinue
    if ($dirs) { $avatarId = $dirs[0].Name }
  }
}
if ([string]::IsNullOrWhiteSpace($avatarId)) {
  Write-Error "No avatar under data\avatars — extract wav2lip256_avatar1 or HF avatar zip."
}

# China HF mirror helps EdgeTTS / transformers cache if needed
if (-not $env:HF_ENDPOINT) { $env:HF_ENDPOINT = "https://hf-mirror.com" }

# Prefer Winget Gyan.FFmpeg if present (edge-tts / av pipelines)
$ffCandidates = @(
  (Get-Command ffmpeg -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source),
  (Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages" -Recurse -Filter "ffmpeg.exe" -ErrorAction SilentlyContinue |
    Select-Object -First 1 -ExpandProperty FullName)
) | Where-Object { $_ }
if ($ffCandidates) {
  $ffDir = Split-Path -Parent $ffCandidates[0]
  if ($env:Path -notlike "*$ffDir*") { $env:Path = "$ffDir;$env:Path" }
}

$port = if ($env:LIVETALKING_PORT) { $env:LIVETALKING_PORT } else { "8010" }

# Public phone path: ECS nginx (signaling) + coturn (media). Load secrets if present.
$turnEnv = Join-Path $PSScriptRoot "livetalking_turn.env.ps1"
if (Test-Path $turnEnv) { . $turnEnv }
if (-not $env:LIVETALKING_TURN_URLS) {
  # CurlHair-style: TURN TLS on public 443 (nginx SNI → coturn)
  $env:LIVETALKING_TURN_URLS = "turns:turn.curlhairai.com:443?transport=tcp"
}

$tsIp = ""
$tsExe = Join-Path ${env:ProgramFiles} "Tailscale\tailscale.exe"
if (Test-Path $tsExe) {
  try { $tsIp = (& $tsExe ip -4 2>$null | Select-Object -First 1).Trim() } catch { }
}
Write-Host "LiveTalking → 0.0.0.0:$port  model=wav2lip  avatar=$avatarId  transport=webrtc"
Write-Host "Local:     http://127.0.0.1:$port/index.html"
Write-Host "Public:    https://acquireenglish.curlhairai.com/livetalking/  (phone: no Tailscale)"
if ($env:LIVETALKING_TURN_USERNAME) {
  Write-Host "TURN:      $($env:LIVETALKING_TURN_URLS)  user=$($env:LIVETALKING_TURN_USERNAME)"
}
if ($tsIp) {
  Write-Host "Tailscale: http://${tsIp}:$port/index.html  (ECS→GPU probe only)"
} else {
  Write-Host "LAN/Tailscale: http://<this-pc-ip>:$port/index.html  (TCP $port + UDP for WebRTC)"
}
# Keep headroom: phones + dashboard probes leave zombie WebRTC sessions until restart.
$maxSession = if ($env:LIVETALKING_MAX_SESSION) { $env:LIVETALKING_MAX_SESSION } else { "10" }
Write-Host "max_session=$maxSession"
& $VenvPython app.py --transport webrtc --model wav2lip --avatar_id $avatarId --listenport $port --max_session $maxSession
