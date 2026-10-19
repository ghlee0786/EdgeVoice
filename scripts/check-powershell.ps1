# PowerShell 스크립트 구문 검사 — 파싱 오류가 하나라도 있으면 실패한다 (ci.yml 이 부른다).
#
#   .\scripts\check-powershell.ps1            # deploy\*.ps1, scripts\*.ps1

$root = Split-Path -Parent $PSScriptRoot
$files = @(Get-ChildItem (Join-Path $root "deploy"), (Join-Path $root "scripts") -Filter *.ps1)
$failed = 0
foreach ($file in $files) {
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors)
    if ($errors.Count -gt 0) {
        $failed++
        foreach ($e in $errors) {
            Write-Host ("{0}:{1}: {2}" -f $file.Name, $e.Extent.StartLineNumber, $e.Message) -ForegroundColor Red
        }
    }
}
Write-Host ("PowerShell 스크립트 {0}개 검사, 오류 있는 파일 {1}개" -f $files.Count, $failed)
exit $(if ($failed -gt 0) { 1 } else { 0 })
