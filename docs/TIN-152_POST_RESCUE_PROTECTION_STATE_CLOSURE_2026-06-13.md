# TIN-152 Post-Rescue Protection State Closure (2026-06-13)

## Issue

- ID: TIN-152
- Title: Implement post-rescue protection state
- Date: 2026-06-13

## Shipped

- Added shared `PostRescueProtectionState` for protection evaluation, breaking actions (`downed`, `objective_task_complete`), and effect multipliers.
- Extended `RescueContractService` grant/clear with movement-speed boost, query seams (`IsTargetPostRescueProtected`, `CancelPostRescueProtection`), and attribute projection.
- Enforced no-grab in `GrabService` (`target_post_rescue_protected`); retained capture rejection in `CaptureService` via shared evaluation.
- Reduced escape request cooldown while protected via `EscapeService.GetEscapeRequestCooldownSeconds` query seam.
- Added `PostRescueProtectionCancellationCaller` wired from construction/station/shrine contextual-task `complete` paths.

## Boundary

- Defensive short-lived state only; no safe-zone immunity or profile persistence.
- No rescue queue or capture rule semantic changes beyond consumer enforcement.

## Validation

```powershell
.\scripts\run-validation.ps1 -ChangedOnly
lune run tests/post_rescue_protection_state.spec.luau
lune run tests/rescue_contract_service_runtime_entrypoint.spec.luau
lune run tests/grab_service_runtime_entrypoint.spec.luau
lune run tests/capture_service_runtime_entrypoint.spec.luau
lune run tests/escape_service_runtime_entrypoint.spec.luau
lune run tests/construction_service_runtime_entrypoint.spec.luau
.\scripts\run-tests.ps1
```

## Deferred

- Studio spot-check for full rescue → protection → re-capture readability loop.
- Additional breaking actions (e.g. traversal-gap block initiation) beyond downed and objective completion.
