param(
    [switch]$ChangedOnly,
    [bool]$AllowSeleneWarnings = $true
)

$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = (Resolve-Path (Join-Path $scriptDir '..')).Path
Set-Location $repoRoot

function Get-ChangedLuauFiles {
    $statusLines = git status --porcelain -- src tests
    if (-not $statusLines) {
        return @()
    }

    $paths = @()
    foreach ($line in $statusLines) {
        if ($line.Length -lt 4) {
            continue
        }

        $path = $line.Substring(3)
        if ($path.Contains(' -> ')) {
            $path = $path.Split(' -> ')[1]
        }

        if ($path.EndsWith('.luau')) {
            $paths += $path
        }
    }

    # Force array return: a single changed file must not unwrap to a string or
    # PowerShell splats @targets character-by-character into stylua/selene/luau-lsp.
    return @($paths | Sort-Object -Unique)
}

$targets = @('src', 'tests')
if ($ChangedOnly) {
    $changed = @(Get-ChangedLuauFiles)
    if ($changed.Count -eq 0) {
        Write-Host '[validate] no changed .luau files under src/tests'
        exit 0
    }

    $targets = @($changed)
    Write-Host "[validate] changed file mode with $($targets.Count) target(s)"
}

$targets = @($targets)

$styluaExit = 0
$seleneExit = 0
$luauLspExit = 0

$luauLspArgs = @(
    'analyze'
    '--platform'
    'roblox'
    '--sourcemap'
    'sourcemap.json'
    '--definitions'
    '@roblox=types/roblox-definitions.d.luau'
)

if ($ChangedOnly) {
    # Known baseline dependency-closure files with existing luau-lsp noise.
    # Keep changed-file validation strict while avoiding unrelated branch debt.
    $baselineIgnore = @(
        'src/ReplicatedStorage/Shared/TinyfolkMovement/PostCrossingBurstLogic.luau'
        'src/ServerScriptService/Services/TinyfolkMovementTraitService.luau'
        'src/ServerScriptService/Services/EscapeService.server.luau'
        'src/ServerScriptService/Services/TransportEscapeService.server.luau'
        'src/ServerScriptService/Services/ProfilePersistenceLifecycle.server.luau'
        'src/ServerScriptService/Services/GiantBuildModeService.server.luau'
        'src/ServerScriptService/Services/ShrineService.server.luau'
        'src/ServerScriptService/Services/RescueContractService.server.luau'
        'src/ServerScriptService/Services/RescueContractQueueService.luau'
        'src/ReplicatedStorage/Shared/GiantRealm/RescueContractHubState.luau'
        'src/ServerScriptService/Services/ResourceFlowState.luau'
        'tests/profile_persistence_lifecycle.spec.luau'
        'tests/giant_build_mode_service_runtime_entrypoint.spec.luau'
        'tests/giant_realm_save_schema.spec.luau'
        'tests/shrine_service_runtime_entrypoint.spec.luau'
        'tests/rescue_contract_service_runtime_entrypoint.spec.luau'
        'src/ServerScriptService/Services/ThirdParty/ProfileStore.luau'
        'tests/harness/MatchSimulation.luau'
    )

    foreach ($path in $baselineIgnore) {
        $luauLspArgs += '--ignore'
        $luauLspArgs += $path
    }
}

Write-Host "[validate] stylua --check --syntax Luau $($targets -join ' ')"
stylua --check --syntax Luau @targets
$styluaExit = $LASTEXITCODE

if ($AllowSeleneWarnings) {
    Write-Host "[validate] selene --allow-warnings $($targets -join ' ')"
    selene --allow-warnings @targets
}
else {
    Write-Host "[validate] selene $($targets -join ' ')"
    selene @targets
}
$seleneExit = $LASTEXITCODE

Write-Host "[validate] luau-lsp $($luauLspArgs -join ' ') $($targets -join ' ')"
$previousErrorActionPreference = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
try {
	luau-lsp @luauLspArgs @targets 2>&1 | Out-Host
	$luauLspExit = $LASTEXITCODE
}
finally {
	$ErrorActionPreference = $previousErrorActionPreference
}

$hasFailure = ($styluaExit -ne 0) -or ($seleneExit -ne 0) -or ($luauLspExit -ne 0)

Write-Host ''
Write-Host "[validate] stylua exit: $styluaExit"
Write-Host "[validate] selene exit: $seleneExit"
Write-Host "[validate] luau-lsp exit: $luauLspExit"

if ($hasFailure) {
    exit 1
}
