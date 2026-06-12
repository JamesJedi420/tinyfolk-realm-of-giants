# TIN-248 Capture Persistence Consumer Wiring Closure (2026-06-12)

## Issue

- ID: TIN-248
- Title: Wire capture persistence rules to escape/grab/rescue consumers
- Date: 2026-06-12

## Shipped

- Wired `EscapeService` route escape and transport boarding paths to consult `_CaptureService_QueryAPI.CanTargetPerformEscapeAction` via `CapturePersistenceRules.EscapeActions.escape_route`.
- Wired `GrabService` counterplay path to consult `CanTargetPerformEscapeAction` via `CapturePersistenceRules.EscapeActions.counterplay`.
- Wired `RescueContractService` request and complete paths to consult `CanTargetPerformEscapeAction` via `CapturePersistenceRules.EscapeActions.rescue_contract`.
- Extended runtime entrypoint specs for escape, grab, and rescue services with blocked-action and capture-query-fault coverage.

## Boundary

- Consumer wiring only — no changes to `CapturePersistenceRules` semantics or profile persistence.
- Fail-open when capture query API is unavailable; fail-closed on query fault.

## Validation

```powershell
.\scripts\run-validation.ps1 -ChangedOnly
lune run tests/escape_service_runtime_entrypoint.spec.luau
lune run tests/grab_service_runtime_entrypoint.spec.luau
lune run tests/rescue_contract_service_runtime_entrypoint.spec.luau
.\scripts\run-tests.ps1
```

## Deferred

- Per-custody escape-action gating beyond catalog validation (future TIN-60 follow-on).
- Profile save/load pipeline for active capture runtime.
