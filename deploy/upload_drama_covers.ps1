# Upload curated drama poster JPEGs to ECS /media/misc/drama-covers/.
# Source: repo tmp/drama_covers/*.jpg (or override with -SourceDir).
$ErrorActionPreference = "Stop"
$root = Join-Path $PSScriptRoot ".." | Resolve-Path
$hostAlias = if ($env:AE_SSH_HOST) { $env:AE_SSH_HOST } else { "acquireenglish" }
$SourceDir = if ($args.Count -ge 1) { $args[0] } else { Join-Path $root "tmp\drama_covers" }
$remoteDir = "/opt/acquireenglish/services/api/media/misc/drama-covers"

if (-not (Test-Path $SourceDir)) {
  throw "Source dir missing: $SourceDir"
}

$files = Get-ChildItem -Path $SourceDir -Filter "*.jpg" -File
if ($files.Count -eq 0) {
  throw "No .jpg files in $SourceDir"
}

Write-Host "Ensuring remote dir on $hostAlias ..."
ssh -o ConnectTimeout=40 -o BatchMode=yes $hostAlias "mkdir -p $remoteDir"

Write-Host "Uploading $($files.Count) covers ..."
foreach ($f in $files) {
  scp -o ConnectTimeout=40 -o BatchMode=yes $f.FullName "${hostAlias}:/tmp/$($f.Name)"
  ssh -o ConnectTimeout=40 -o BatchMode=yes $hostAlias "mv /tmp/$($f.Name) $remoteDir/$($f.Name) && chmod 644 $remoteDir/$($f.Name)"
  Write-Host "  ok $($f.Name)"
}

Write-Host "Verify public URLs:"
foreach ($f in $files) {
  $url = "https://acquireenglish.curlhairai.com/media/misc/drama-covers/$($f.Name)"
  $code = curl.exe -s -o NUL -w "%{http_code}" $url
  Write-Host "  $code $url"
}
