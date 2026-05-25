$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = (Resolve-Path (Join-Path $scriptDir '..')).Path

$lune = Get-Command lune -ErrorAction SilentlyContinue
if (-not $lune) {
    Write-Error 'lune is not installed. Install it with: & "$env:LOCALAPPDATA\Microsoft\WindowsApps\winget.exe" install --id Lune.Lune --exact --source winget --accept-source-agreements --accept-package-agreements'
}

$testFiles = @(
    'tests\event_log_state.spec.luau',
    'tests\event_log_service_runtime_entrypoint.spec.luau',
    'tests\published_client_teleport_evidence.spec.luau',
    'tests\profile_teleport_handoff_service_runtime_entrypoint.spec.luau',
    'tests\upgrade_progression_logic.spec.luau',
    'tests\remote_control_station_state.spec.luau',
    'tests\remote_control_station_service_runtime_entrypoint.spec.luau',
    'tests\emergency_reinforcement_state.spec.luau',
    'tests\emergency_reinforcement_service_runtime_entrypoint.spec.luau',
    'tests\capture_state.spec.luau',
    'tests\capture_service_runtime_entrypoint.spec.luau',
    'tests\score_state.spec.luau',
    'tests\score_service_runtime_entrypoint.spec.luau',
    'tests\realm_objective_state.spec.luau',
    'tests\realm_objective_service_runtime_entrypoint.spec.luau',
    'tests\tinyfolk_giant_proximity_warning.spec.luau',
    'tests\tinyfolk_raid_status_projection.spec.luau',
    'tests\giant_threat_stage_logic.spec.luau',
    'tests\timed_condition_states_runtime_entrypoint.spec.luau',
    'tests\fallback_escape_state.spec.luau',
    'tests\snare_trap_state.spec.luau',
    'tests\tinyfolk_status_service_runtime_entrypoint.spec.luau',
    'tests\memorystore_structure_policy.spec.luau',
    'tests\realm_admission_queue_state.spec.luau',
    'tests\realm_admission_queue_store.spec.luau',
    'tests\realm_admission_queue_processor.spec.luau',
    'tests\realm_metadata_registry.spec.luau',
    'tests\district_placement_assembly_selection_runtime_entrypoint.spec.luau',
    'tests\active_realm_capacity_state.spec.luau',
    'tests\active_realm_capacity_store.spec.luau',
    'tests\rescue_contract_state.spec.luau',
    'tests\rescue_contract_service_runtime_entrypoint.spec.luau',
    'tests\headless_match_simulation.spec.luau'
)

foreach ($relativeTestPath in $testFiles) {
    $testFile = Join-Path $repoRoot $relativeTestPath
    & $lune.Source run $testFile
}
