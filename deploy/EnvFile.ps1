# .env 읽기·쓰기 (setup-server.ps1 · update-server.ps1 이 dot-source 한다). UTF-8(BOM 없음)으로 쓴다.

function Read-EnvLines([string]$Path) {
    if (Test-Path $Path) { return @(Get-Content $Path -Encoding UTF8) }
    return @()
}

function Get-EnvValue([string[]]$Lines, [string]$Key) {
    foreach ($line in $Lines) {
        if ($line -match "^\s*$Key=(.*)$") { return $Matches[1].Trim() }
    }
    return ""
}

function Set-EnvValue([string[]]$Lines, [string]$Key, [string]$Value) {
    $found = $false
    $out = foreach ($line in $Lines) {
        if ($line -match "^\s*$Key=") { $found = $true; "$Key=$Value" } else { $line }
    }
    if (-not $found) { $out = @($out) + "$Key=$Value" }
    return @($out)
}

function Write-EnvLines([string]$Path, [string[]]$Lines) {
    [System.IO.File]::WriteAllLines($Path, [string[]]$Lines, (New-Object System.Text.UTF8Encoding $false))
}
