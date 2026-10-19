# EdgeVoice 설치 프로그램 만들기 — release.yml 과 ci.yml 이 같은 이 스크립트를 부른다.
#
#   .\scripts\build-installer.ps1 -Version 1.2.3     # publish → ISCC → clients\dotnet\installer\Output\EdgeVoice-Setup-1.2.3.exe
#
# Inno Setup 6 이 필요하다 (CI 는 choco install innosetup). ISCC.exe 는 Program Files · 사용자 설치 위치에서 찾는다.

param(
    # 앱 버전 (태그 v1.2.3 → 1.2.3). 0.0.0 = 개발 빌드
    [string]$Version = "0.0.0",
    # 이미 publish 한 폴더를 쓴다
    [switch]$SkipPublish
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$publish = Join-Path $root "publish\win-x64"

if (-not $SkipPublish) {
    & dotnet publish (Join-Path $root "clients\dotnet\src\EdgeVoice.Agent.Desktop\EdgeVoice.Agent.Desktop.csproj") `
        -c Release -r win-x64 --self-contained true `
        -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true `
        "-p:Version=$Version" -o $publish
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

$iscc = @(
    "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
    "$env:ProgramFiles\Inno Setup 6\ISCC.exe",
    "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe"
) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
if (-not $iscc) {
    Write-Error "Inno Setup 6 (ISCC.exe) 을 찾지 못했습니다. https://jrsoftware.org/isdl.php 또는 'choco install innosetup'"
}

& $iscc "/DAppVersion=$Version" "/DSourceDir=$publish" (Join-Path $root "clients\dotnet\installer\EdgeVoice.iss")
exit $LASTEXITCODE
