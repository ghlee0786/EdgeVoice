# EdgeVoice 모델 받기 — compose 파일의 기본 모델(과 .env 의 바꾼 값)을 읽어 HuggingFace 에서 받는다.
#
#   .\download-models.ps1                                   # 이 폴더의 docker-compose.yml · .env · models
#   .\download-models.ps1 -ComposeFile ..\docker-compose.dev.yml -ModelDir ..\models
#
# - 모델 이름은 compose 파일 한 곳에서 읽는다 (llm: ${LLM_MODEL:-…}, stt: ${STT_MODEL:-…}, embedding: MODEL_NAME=…).
# - 받는 일은 docker 안(python + huggingface_hub)에서 한다 — 이 PC 에 python 이 없어도 된다.
# - 모델마다 전체 크기와 남은 크기를 보여 주고, 이미 다 받은 모델은 건너뛴다(받다 끊긴 것은 이어 받는다).
# - 모델은 각자의 라이선스를 따른다 (HuggingFace 모델 페이지 참고).

param(
    [string]$ComposeFile = (Join-Path $PSScriptRoot "docker-compose.yml"),
    [string]$EnvFile = "",
    [string]$ModelDir = "",
    # 받을 목록과 크기만 보여 주고 받지는 않는다
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
$ComposeDir = Split-Path -Parent (Resolve-Path $ComposeFile)
if (-not $EnvFile) { $EnvFile = Join-Path $ComposeDir ".env" }

# .env 값 (없으면 빈 표)
$DotEnv = @{}
if (Test-Path $EnvFile) {
    foreach ($line in Get-Content $EnvFile -Encoding UTF8) {
        if ($line -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$') { $DotEnv[$Matches[1]] = $Matches[2].Trim() }
    }
}

if (-not $ModelDir) {
    $ModelDir = if ($DotEnv["MODEL_CACHE_PATH"]) { $DotEnv["MODEL_CACHE_PATH"] } else { "./models" }
}
if (-not [System.IO.Path]::IsPathRooted($ModelDir)) { $ModelDir = Join-Path $ComposeDir $ModelDir }
New-Item -ItemType Directory -Force $ModelDir | Out-Null
$ModelDir = (Resolve-Path $ModelDir).Path

$Compose = Get-Content $ComposeFile -Raw -Encoding UTF8

# compose 의 서비스 하나 (두 칸 들여쓴 '이름:' 부터 다음 서비스 전까지)
function Get-ServiceBlock([string]$Name) {
    $pattern = '(?ms)^  ' + [regex]::Escape($Name) + ':\s*$(.*?)(?=^  [A-Za-z][\w-]*:\s*$|^\S|\z)'
    if ($Compose -match $pattern) { return $Matches[1] }
    return ""
}

# '${VAR:-기본값}' 은 .env 값 또는 기본값, 그냥 값은 그대로
function Resolve-Value([string]$Text) {
    if ($Text -match '^\$\{(\w+):-([^}]*)\}$') {
        if ($DotEnv[$Matches[1]]) { return $DotEnv[$Matches[1]] }
        return $Matches[2]
    }
    return $Text
}

function Find-Setting([string]$Block, [string]$Pattern) {
    if ($Block -match $Pattern) { return Resolve-Value $Matches[1].Trim("'", '"') }
    return $null
}

$llmBlock = Get-ServiceBlock "llm"
$llm = Find-Setting $llmBlock '--model\s*\r?\n\s*-\s*(\S+)'
if (-not $llm) { $llm = Find-Setting $llmBlock 'MODEL_NAME=(\S+)' }
$stt = Find-Setting (Get-ServiceBlock "stt") 'MODEL_SIZE=(\S+)'
$embedding = Find-Setting (Get-ServiceBlock "embedding") 'MODEL_NAME=(\S+)'
$ttsEngine = Find-Setting (Get-ServiceBlock "tts") 'TTS_ENGINE=(\S+)'

# faster-whisper 의 짧은 이름 → HuggingFace 저장소 (faster_whisper.utils._MODELS 와 같게)
$WhisperRepos = @{
    "large-v3-turbo" = "mobiuslabsgmbh/faster-whisper-large-v3-turbo"; "turbo" = "mobiuslabsgmbh/faster-whisper-large-v3-turbo"
    "large-v3" = "Systran/faster-whisper-large-v3"; "medium" = "Systran/faster-whisper-medium"
    "small" = "Systran/faster-whisper-small"; "base" = "Systran/faster-whisper-base"
}
if ($stt -and $WhisperRepos.ContainsKey($stt)) { $stt = $WhisperRepos[$stt] }

# 받을 모델: 이름 · 저장소 · 받는 곳 (compose 가 붙이는 자리와 같게)
#   cache  = HuggingFace 캐시(hub) — 서비스가 /root/.cache/huggingface 로 읽는다
#   local  = 폴더에 파일을 바로 — 서비스가 /models 로 읽는다
$Models = @()
if ($llm) { $Models += [pscustomobject]@{ Name = "LLM"; Repo = $llm; Mode = "cache"; Dir = "llm/hub"; Volume = "" } }
if ($embedding) { $Models += [pscustomobject]@{ Name = "임베딩"; Repo = $embedding; Mode = "local"; Dir = "embedding"; Volume = "" } }
if ($stt -and $stt.Contains("/")) { $Models += [pscustomobject]@{ Name = "음성 인식(STT)"; Repo = $stt; Mode = "cache"; Dir = "hub"; Volume = "edgevoice-stt-hf-cache" } }
if ($ttsEngine -eq "melo") {
    $Models += [pscustomobject]@{ Name = "답변 음성(MeloTTS 한국어)"; Repo = "myshell-ai/MeloTTS-Korean"; Mode = "cache"; Dir = "hub"; Volume = "edgevoice-tts-hf-cache" }
    $Models += [pscustomobject]@{ Name = "답변 음성(한국어 BERT)"; Repo = "kykim/bert-kor-base"; Mode = "cache"; Dir = "hub"; Volume = "edgevoice-tts-hf-cache" }
}

function Format-GB([double]$Bytes) { return "{0:N1}GB" -f ($Bytes / 1GB) }

function Get-RepoSize([string]$Repo) {
    $headers = @{}
    if ($DotEnv["HF_TOKEN"]) { $headers["Authorization"] = "Bearer " + $DotEnv["HF_TOKEN"] }
    try {
        $info = Invoke-RestMethod -Uri "https://huggingface.co/api/models/$Repo`?blobs=true" -Headers $headers -TimeoutSec 30
        return [double](($info.siblings | Measure-Object -Property size -Sum).Sum)
    } catch {
        return 0
    }
}

# 이 PC 에 이미 있는 크기 (docker 볼륨 안은 받으면서 건너뛰므로 0 으로 본다)
function Get-LocalSize($Model) {
    if ($Model.Volume) { return 0 }
    # 캐시는 hub 폴더 전체를 잰다 (받은 파일은 hub/blobs 에 모일 수 있다)
    $path = Join-Path $ModelDir $Model.Dir
    if (-not (Test-Path $path)) { return 0 }
    return [double]((Get-ChildItem $path -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum)
}

Write-Host "EdgeVoice 모델 받기 — $ModelDir" -ForegroundColor Cyan
$todo = @()
$remainingTotal = 0
foreach ($m in $Models) {
    $total = Get-RepoSize $m.Repo
    $have = Get-LocalSize $m
    $left = [Math]::Max([double]0, $total - $have)
    $remainingTotal += $left
    if ($total -gt 0 -and $left -lt $total * 0.01) {
        Write-Host ("  [있음] {0}: {1} ({2})" -f $m.Name, $m.Repo, (Format-GB $total)) -ForegroundColor Green
        continue
    }
    Write-Host ("  [받기] {0}: {1} — 전체 {2} · 남은 약 {3}" -f $m.Name, $m.Repo, (Format-GB $total), (Format-GB $left))
    $todo += $m
}

if ($todo.Count -eq 0) {
    Write-Host "모든 모델이 이미 있습니다." -ForegroundColor Green
    exit 0
}
if ($DryRun) { exit 0 }
Write-Host ("남은 크기 약 {0} — 인터넷 속도에 따라 오래 걸립니다. 끊기면 다시 실행하면 이어 받습니다." -f (Format-GB $remainingTotal)) -ForegroundColor Yellow

# docker 안에서 받기 (진행 막대는 huggingface_hub 가 보여 준다)
$commands = @("pip install -q --disable-pip-version-check 'huggingface_hub>=0.34'")
$mounts = @("-v", "${ModelDir}:/m")
foreach ($m in $todo) {
    $root = if ($m.Volume) { "/v-" + $m.Volume } else { "/m" }
    if ($m.Volume -and -not ($mounts -contains "$($m.Volume):$root")) { $mounts += @("-v", "$($m.Volume):$root") }
    $target = if ($m.Mode -eq "cache") { "--cache-dir $root/$($m.Dir)" } else { "--local-dir $root/$($m.Dir)" }
    $commands += "echo '== $($m.Repo)' && hf download $($m.Repo) $target"
}
$dockerArgs = @("run", "--rm", "-e", "HF_TOKEN=$($DotEnv['HF_TOKEN'])", "-e", "HF_HUB_ENABLE_HF_TRANSFER=0") + $mounts + @("python:3.11-slim", "sh", "-c", ($commands -join " && "))
& docker @dockerArgs
if ($LASTEXITCODE -ne 0) {
    Write-Host "모델을 다 받지 못했습니다 (종료 코드 $LASTEXITCODE). 다시 실행하면 이어 받습니다." -ForegroundColor Red
    exit $LASTEXITCODE
}
Write-Host "모델 받기 완료" -ForegroundColor Green
