# EdgeVoice AI 서버를 한 버전으로 올린다 — 설치 프로그램의 [AI 서버] 설치·업데이트(setup-server.ps1)와
# CD(.github/workflows/deploy.yml, self-hosted runner)가 같은 이 스크립트를 쓴다.
#
#   .\update-server.ps1 -Version v1.2.3
#   .\update-server.ps1 -Version v1.2.3 -SourceDir C:\runner\_work\EdgeVoice\EdgeVoice   # 새 릴리스의 서버 파일도 함께
#   .\update-server.ps1 -Version v1.2.3 -DryRun                                         # 실행할 명령만 보여 준다
#
#   1. (-SourceDir) compose 파일·서버가 마운트하는 파일을 새 것으로 바꾼다 (.env · models · logs 는 그대로)
#   2. .env 의 EDGEVOICE_VERSION 을 새 태그로 → docker compose pull → up -d (모델·DB 볼륨은 그대로)
#   3. healthcheck 가 있는 서비스가 모두 healthy 가 될 때까지 기다린다
#   4. 실패하면 이전 태그로 되돌려 up -d 하고 실패로 끝낸다

param(
    [string]$Version = "",
    [string]$SourceDir = "",
    [int]$HealthTimeoutMinutes = 15,
    [switch]$DryRun,
    # 시험용: health 가 끝내 healthy 가 되지 않은 것처럼 (되돌리기 확인)
    [switch]$SimulateUnhealthy
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "EnvFile.ps1")
Set-Location $PSScriptRoot
$envPath = Join-Path $PSScriptRoot ".env"

function Invoke-Docker([string[]]$DockerArgs) {
    Write-Output ("docker " + ($DockerArgs -join " "))
    if ($DryRun) { return }
    & docker @DockerArgs | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "docker $($DockerArgs -join ' ') 실패 (종료 코드 $LASTEXITCODE)" }
}

function Set-Version([string]$Tag) {
    Write-Output "EDGEVOICE_VERSION=$Tag"
    if ($DryRun) { return }
    Write-EnvLines $envPath (Set-EnvValue (Read-EnvLines $envPath) "EDGEVOICE_VERSION" $Tag)
}

# 'docker compose ps' 의 '서비스|health' 줄들: healthcheck 가 있는 서비스가 모두 healthy 면 true
function Test-AllHealthy([string[]]$Lines) {
    $checked = @($Lines | Where-Object { $_ -match '^[^|]+\|\S+' })
    return $checked.Count -gt 0 -and -not ($checked | Where-Object { $_ -notmatch '\|healthy$' })
}

function Wait-Healthy {
    if ($DryRun) { return -not $SimulateUnhealthy }
    $until = (Get-Date).AddMinutes($HealthTimeoutMinutes)
    while ((Get-Date) -lt $until) {
        $lines = @(& docker compose ps --format "{{.Service}}|{{.Health}}")
        if (Test-AllHealthy $lines) { return $true }
        Start-Sleep -Seconds 10
    }
    Write-Host "제한 시간($HealthTimeoutMinutes 분) 안에 healthy 가 되지 않은 서비스:" -ForegroundColor Red
    & docker compose ps --format "{{.Service}}|{{.Health}}" | Where-Object { $_ -notmatch '\|healthy$' } | Out-Host
    return $false
}

# 1. 서버 파일 (설치 프로그램 EdgeVoice.iss 의 [Files] 'server' 와 같은 목록)
if ($SourceDir) {
    $copies = @(
        @("deploy\docker-compose.yml", "."), @("deploy\.env.example", "."), @("deploy\*.ps1", "."),
        @("shared", "shared"), @("services\llm\edgevoice_guard", "services\llm\edgevoice_guard"),
        @("services\backend\static", "services\backend\static"), @("config\mcp", "config\mcp"),
        @("config\postgres\init.sql", "config\postgres"), @("config\searxng\settings.yml", "config\searxng")
    )
    foreach ($c in $copies) {
        Write-Output "copy $($c[0]) -> $($c[1])"
        if ($DryRun) { continue }
        $target = Join-Path $PSScriptRoot $c[1]
        $source = Join-Path $SourceDir $c[0]
        if ((Test-Path $source -PathType Container)) {
            if (Test-Path $target) { Remove-Item -Recurse -Force $target }
            Copy-Item -Recurse $source $target -Exclude "__pycache__"
        } else {
            New-Item -ItemType Directory -Force $target | Out-Null
            Copy-Item $source $target -Force
        }
    }
}

# 2. 새 태그로 받고 띄우기
$previous = Get-EnvValue (Read-EnvLines $envPath) "EDGEVOICE_VERSION"
if (-not $Version) { $Version = $previous }
if (-not $Version) { $Version = "latest" }
Write-Output "EdgeVoice AI 서버: $previous -> $Version"
Set-Version $Version
$ok = $false
try {
    Invoke-Docker @("compose", "pull")
    Invoke-Docker @("compose", "up", "-d")
    # 3. health
    $ok = Wait-Healthy
} catch {
    # 받지 못한 태그(릴리스 이미지가 아직 없음) 등 — 아래에서 되돌린다
    Write-Output "오류: $_"
}
if ($ok) {
    Write-Output "완료: $Version (모든 서비스 healthy)"
    exit 0
}

# 4. 되돌리기
if ($previous -and $previous -ne $Version) {
    Write-Output "되돌리기: $Version -> $previous"
    Set-Version $previous
    Invoke-Docker @("compose", "up", "-d")
}
Write-Output "실패: $Version 이(가) 준비되지 않았습니다"
exit 1
