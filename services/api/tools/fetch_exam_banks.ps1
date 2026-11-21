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

# K12 open banks (2026-11): taxonomy English + RACE (+ CLOTH/SC-Ques when mirrors work)
Ensure-Clone "cn-math-taxonomy" "https://github.com/xiaoyang111222/cn-math-taxonomy.git"
Ensure-Clone "SC-Ques" "https://github.com/ai4ed/SC-Ques.git"

# RACE via ModelScope (parquet zip; CN-friendly)
$raceMs = Join-Path $Root "RACE_ms"
if (-not (Test-Path (Join-Path $raceMs ".git"))) {
  Write-Host "CLONE RACE_ms (modelscope) ..."
  git clone --depth 1 "https://www.modelscope.cn/datasets/modelscope/race.git" RACE_ms
  if ($LASTEXITCODE -eq 0) { Write-Host "OK RACE_ms" } else { Write-Warning "FAILED RACE_ms" }
} else {
  Write-Host "EXISTS RACE_ms"
}
$raceZip = Join-Path $raceMs "race.zip"
$raceExtracted = Join-Path $raceMs "extracted"
if ((Test-Path $raceZip) -and -not (Test-Path (Join-Path $raceExtracted "_ok.txt"))) {
  New-Item -ItemType Directory -Force -Path $raceExtracted | Out-Null
  tar -xf $raceZip -C $raceExtracted
  Set-Content (Join-Path $raceExtracted "_ok.txt") "ok"
  Write-Host "EXTRACTED RACE_ms/race.zip"
}

# CLOTH (academic; official host often blocked — place CLOTH.tar.gz manually if needed)
$clothDir = Join-Path $Root "CLOTH"
New-Item -ItemType Directory -Force -Path $clothDir | Out-Null
$clothTar = Join-Path $clothDir "CLOTH.tar.gz"
if (-not (Test-Path (Join-Path $clothDir "_fetched.txt"))) {
  Write-Host "DOWNLOAD CLOTH ..."
  curl.exe -L --connect-timeout 20 --max-time 300 -o $clothTar "http://www.qizhexie.com/data/CLOTH.tar.gz"
  if ((Test-Path $clothTar) -and ((Get-Item $clothTar).Length -gt 100000)) {
    tar -xzf $clothTar -C $clothDir
    Set-Content (Join-Path $clothDir "_fetched.txt") "CLOTH.tar.gz"
    Write-Host "OK CLOTH"
  } else {
    Write-Warning "CLOTH not downloaded — put CLOTH.tar.gz into $clothDir then re-run import_k12_open_banks.py"
  }
} else { Write-Host "EXISTS CLOTH" }

# SC-Ques data archive (Dropbox; often blocked)
$scData = Join-Path $Root "SC-Ques\datasets"
New-Item -ItemType Directory -Force -Path $scData | Out-Null
$scTar = Join-Path $scData "SC-Ques.tar.gz"
if (-not (Test-Path (Join-Path $scData "_fetched.txt"))) {
  Write-Host "DOWNLOAD SC-Ques archive ..."
  curl.exe -L --connect-timeout 20 --max-time 300 -o $scTar "https://www.dropbox.com/s/lzznin2hxt6rmft/SC-Ques.tar.gz?dl=1"
  if ((Test-Path $scTar) -and ((Get-Item $scTar).Length -gt 100000)) {
    tar -xzf $scTar -C $scData
    Set-Content (Join-Path $scData "_fetched.txt") "SC-Ques.tar.gz"
    Write-Host "OK SC-Ques"
  } else {
    Write-Warning "SC-Ques archive missing — place SC-Ques.tar.gz under $scData"
  }
} else { Write-Host "EXISTS SC-Ques data" }

Write-Host "DONE fetch into $Root"
Get-ChildItem $Root -Directory | ForEach-Object { $_.Name }
