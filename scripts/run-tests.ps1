$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = (Resolve-Path (Join-Path $scriptDir '..')).Path

$lune = Get-Command lune -ErrorAction SilentlyContinue
if (-not $lune) {
    Write-Error 'lune is not installed. Install it with: & "$env:LOCALAPPDATA\Microsoft\WindowsApps\winget.exe" install --id Lune.Lune --exact --source winget --accept-source-agreements --accept-package-agreements'
}

$testFile = Join-Path $repoRoot 'tests\upgrade_progression_logic.spec.luau'
& $lune.Source run $testFile
