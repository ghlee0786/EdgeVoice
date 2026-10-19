# EdgeVoice 모델 받기 (개발용) — deploy/download-models.ps1 을 docker compose 파일 기준으로 부른다.
# 모델 이름은 compose 파일의 기본값(과 .env)에서 읽으므로 이 스크립트에는 모델 이름이 없다.
#
#   .\scripts\download-models.ps1                   # docker-compose.dev.yml → .\models
#   .\scripts\download-models.ps1 -EnvType jetson   # docker-compose.jetson.yml
#   .\scripts\download-models.ps1 -DryRun           # 받을 목록·크기만

param(
    [ValidateSet("dev", "jetson")]
    [string]$EnvType = "dev",
    [switch]$DryRun
)

$root = Split-Path -Parent $PSScriptRoot
& (Join-Path $root "deploy\download-models.ps1") `
    -ComposeFile (Join-Path $root "docker-compose.$EnvType.yml") `
    -EnvFile (Join-Path $root ".env") `
    -ModelDir (Join-Path $root "models") `
    -DryRun:$DryRun
exit $LASTEXITCODE
