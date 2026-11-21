# Shallow-fetch exam bank vendors into data/exam_bank_vendor/
# Usage: powershell -File services/api/tools/fetch_exam_banks.ps1
$ErrorActionPreference = "Continue"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..\data\exam_bank_vendor")
New-Item -ItemType Directory -Force -Path $Root | Out-Null
Set-Location $Root

function Ensure-Clone([string]$Name, [string]$Url, [string]$ExtraArgs = "") {
  $dest = Join-Path $Root $Name
  if (Test-Path (Join-Path $dest ".git")) {
    Write-Host "EXISTS $Name"
    return
  }
  Write-Host "CLONE $Name ..."
  $args = @("clone", "--depth", "1", "--single-branch")
  if ($ExtraArgs) { $args += $ExtraArgs.Split(" ") }
  $args += @($Url, $Name)
  & git @args
  if ($LASTEXITCODE -ne 0) {
    # Fallback: ghproxy mirror
    $mirror = $Url -replace '^https://github.com/', 'https://ghproxy.net/https://github.com/'
    Write-Host "RETRY via ghproxy $Name"
    if (Test-Path $dest) { Remove-Item -Recurse -Force $dest -ErrorAction SilentlyContinue }
    & git clone --depth 1 --single-branch $mirror $Name
  }
  if ($LASTEXITCODE -ne 0) {
    Write-Warning "FAILED clone $Name"
  } else {
    Write-Host "OK $Name"
  }
}

function Ensure-Release([string]$Name, [string]$ApiUrl, [string]$AssetMatch) {
  $dest = Join-Path $Root $Name
  New-Item -ItemType Directory -Force -Path $dest | Out-Null
  $marker = Join-Path $dest "_fetched.txt"
  if (Test-Path $marker) {
    Write-Host "EXISTS release $Name"
    return
  }
  Write-Host "RELEASE $Name ..."
  try {
    $rel = Invoke-RestMethod -Uri $ApiUrl -Headers @{ "User-Agent" = "AcquireEnglish-fetch" }
    $asset = $rel.assets | Where-Object { $_.name -match $AssetMatch } | Select-Object -First 1
    if (-not $asset) {
      Write-Warning "No asset matching $AssetMatch for $Name"
      return
    }
    $out = Join-Path $dest $asset.name
    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $out -Headers @{ "User-Agent" = "AcquireEnglish-fetch" }
    Set-Content -Path $marker -Value $asset.name
    Write-Host "OK release $($asset.name)"
  } catch {
    Write-Warning "FAILED release $Name : $_"
  }
}

# Smaller / structured first
Ensure-Clone "ielts-ai-dataset" "https://github.com/LuchoBazz/ielts-ai-dataset.git"
Ensure-Clone "fluova" "https://github.com/emrecpn/fluova.git"
Ensure-Clone "toefl-ielts-prep" "https://github.com/Looffeeuu/toefl-ielts-prep.git"
Ensure-Clone "pteracai" "https://github.com/fthrvi/pteracai.git"
Ensure-Clone "ExpressAI-Exams" "https://github.com/ExpressAI/Exams.git"
Ensure-Clone "AI-Gaokao" "https://github.com/ExpressAI/AI-Gaokao.git"
Ensure-Clone "SmartGaokaoPastPapers" "https://github.com/guorentao/SmartGaokaoPastPapers.git"
Ensure-Clone "structured-kaoyan-english" "https://github.com/LIziak112/structured-kaoyan-english.git"
Ensure-Clone "gaokao-2026-english-exam" "https://github.com/daligao/gaokao-2026-english-exam.git"
Ensure-Clone "cet4-gongyining" "https://github.com/gongyining0601/cet4.git"
Ensure-Clone "english-question-banks" "https://github.com/wssfk12138/english-question-banks.git"
Ensure-Clone "PET-SkoolPlus" "https://github.com/SkoolPlus/PET.git"
Ensure-Clone "ielts-mock" "https://github.com/yanboishere/ielts-mock.git"

# Large CET past papers (~2.3GB) — still clone for full access per plan option 3
Ensure-Clone "English-past-papers" "https://github.com/Aron0525/English-past-papers.git"

# ESQ release assets (CET / kaoyan)
Ensure-Release "esq-releases" "https://api.github.com/repos/wssfk12138/english-question-banks/releases/latest" "\.(esq|zip)$"

# HuggingFace GAOKAO-Bench (english subsets via git LFS if available)
Ensure-Clone "gaokao-bench" "https://huggingface.co/datasets/RUCAIBox/gaokao-bench"

Write-Host "DONE fetch into $Root"
Get-ChildItem $Root -Directory | ForEach-Object { $_.Name }
