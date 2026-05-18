$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = (Resolve-Path (Join-Path $scriptDir '..')).Path

$lune = Get-Command lune -ErrorAction SilentlyContinue
if (-not $lune) {
    Write-Error 'lune is not installed. Install it with: & "$env:LOCALAPPDATA\Microsoft\WindowsApps\winget.exe" install --id Lune.Lune --exact --source winget --accept-source-agreements --accept-package-agreements'
}

$testFiles = @(
    'tests\upgrade_progression_logic.spec.luau',
    'tests\emergency_reinforcement_state.spec.luau',
    'tests\emergency_reinforcement_service_runtime_entrypoint.spec.luau',
    'tests\capture_state.spec.luau',
    'tests\capture_service_runtime_entrypoint.spec.luau',
    'tests\score_state.spec.luau',
    'tests\score_service_runtime_entrypoint.spec.luau',
    'tests\rescue_contract_state.spec.luau',
    'tests\rescue_contract_service_runtime_entrypoint.spec.luau',
    'tests\headless_match_simulation.spec.luau'
)

foreach ($relativeTestPath in $testFiles) {
    $testFile = Join-Path $repoRoot $relativeTestPath
    & $lune.Source run $testFile
}
