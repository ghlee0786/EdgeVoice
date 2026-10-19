# EdgeVoice AI 서버 준비 — 설치 프로그램이 설치·업데이트 뒤에 실행한다 (시작 메뉴 'EdgeVoice AI 서버 준비' 로 다시 실행 가능).
#
#   0. .env 준비: 없으면 .env.example 로 만들고, 비밀 값(change-me)을 무작위로 채우고, 이미지 태그·HF 토큰을 넣는다
#   1. Docker Desktop · NVIDIA GPU 확인
#   2. 모델 받기 (download-models.ps1 — 이미 있으면 건너뜀)
#   3. update-server.ps1 — 태그를 올려 pull · up -d · health 확인 (실패하면 이전 태그로 되돌림, CD 와 같은 스크립트)

param(
    # 받을 이미지 태그 (설치 프로그램이 v<버전> 을 넘긴다). 비우면 .env 값 그대로
    [string]$Version = "",
    # HuggingFace 토큰 (선택). 비우면 .env 값 그대로
    [string]$HfToken = "",
    [switch]$SkipModels,
    # .env 만 준비하고 끝낸다 (시험용)
    [switch]$EnvOnly
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "EnvFile.ps1")
Set-Location $PSScriptRoot
$Host.UI.RawUI.WindowTitle = "EdgeVoice AI 서버 준비"

function Fail([string]$Message) {
    Write-Host ""
    Write-Host $Message -ForegroundColor Red
    Write-Host "문제를 고친 뒤 시작 메뉴의 'EdgeVoice AI 서버 준비' 를 다시 실행하세요."
    Read-Host "Enter 를 누르면 닫습니다"
    exit 1
}

Write-Host "EdgeVoice AI 서버 준비 — $PSScriptRoot" -ForegroundColor Cyan

# 0. .env
function New-Secret {
    $bytes = New-Object byte[] 24
    [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    return ([System.BitConverter]::ToString($bytes) -replace "-", "").ToLower()
}

if (-not (Test-Path ".env")) {
    if (-not (Test-Path ".env.example")) { Fail ".env.example 이 없습니다." }
    Copy-Item ".env.example" ".env"
}
$lines = Read-EnvLines (Join-Path $PSScriptRoot ".env")
foreach ($key in "POSTGRES_PASSWORD", "SEARXNG_SECRET", "SESSION_SECRET") {
    # 공개된 기본값(change-me)이면 무작위로 바꾼다 — 이미 바꾼 값은 그대로 (DB 비밀번호가 바뀌면 기존 DB 에 못 붙는다)
    if (($lines | Where-Object { $_ -match "^\s*$key=(change-me)?\s*$" }) -or -not ($lines | Where-Object { $_ -match "^\s*$key=" })) {
        $lines = Set-EnvValue $lines $key (New-Secret)
    }
}
if ($HfToken) { $lines = Set-EnvValue $lines "HF_TOKEN" $HfToken }
Write-EnvLines (Join-Path $PSScriptRoot ".env") $lines
if ($EnvOnly) { exit 0 }

# 1. Docker · GPU
& docker info *> $null
if ($LASTEXITCODE -ne 0) {
    Fail "Docker Desktop 이 설치되어 있지 않거나 켜져 있지 않습니다. https://www.docker.com/products/docker-desktop/ 에서 설치하고 켜 주세요."
}
if (-not (Get-Command nvidia-smi -ErrorAction SilentlyContinue)) {
    Write-Host "NVIDIA GPU 드라이버(nvidia-smi)를 찾지 못했습니다. AI 서비스(LLM·STT·TTS)는 NVIDIA GPU 가 필요합니다." -ForegroundColor Yellow
}

# 2. 모델
if (-not $SkipModels) {
    & (Join-Path $PSScriptRoot "download-models.ps1")
    if ($LASTEXITCODE -ne 0) { Fail "모델을 다 받지 못했습니다." }
}

# 3. 이미지 받기 · 시작 · health (이전 태그로 되돌리기 포함)
Write-Host "서비스 이미지를 받고 시작합니다 (처음에는 수 GB, 언어 모델 준비까지 몇 분)..." -ForegroundColor Cyan
& (Join-Path $PSScriptRoot "update-server.ps1") -Version $Version
if ($LASTEXITCODE -ne 0) { Fail "서비스를 준비하지 못했습니다 (인터넷·ghcr.io 접속, docker compose logs 확인)." }

Write-Host ""
Write-Host "AI 서버가 준비되었습니다." -ForegroundColor Green
Start-Sleep -Seconds 8
