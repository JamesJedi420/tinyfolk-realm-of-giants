# TIN-73 Maximum Captivity Duration Kickoff (2026-06-13)

## Issue

- ID: TIN-73
- Title: Implement maximum captivity duration
- Milestone: Capture, Rescue, and Routing
- Linear: https://linear.app/spectranoir/issue/TIN-73/implement-maximum-captivity-duration

## Goal

Prevent indefinite player imprisonment with hard captured/contained duration caps, transfer-safe anchors, and safe-return fallback after threshold.

## Scope

- Add shared `CaptivityDurationState` for captured/contained deadline evaluation, transfer preservation, and timeout fallback mapping.
- Extend `CaptureState` records with immutable `captivityAnchorAt`, `containmentPhase`, and custody-transfer/promote-to-contained transitions.
- Wire `CaptureService` timeout pruning to apply safe-return fallback via `CaptivitySafeReturnCaller` / `EscapeService` seam.
- Extend config with explicit `MaxCapturedDurationSeconds` and `MaxContainedDurationSeconds`.

## Boundary

- No Giant-to-Giant custody transfer gameplay UX (TIN-71); only server rules + query seam for transfer preservation.
- No containment structure placement system (TIN-61); contained phase is a record transition only.
- No profile persistence of active captivity runtime.

## Validation

```powershell
.\scripts\run-validation.ps1 -ChangedOnly
lune run tests/captivity_duration_state.spec.luau
lune run tests/capture_state.spec.luau
lune run tests/capture_persistence_rules.spec.luau
lune run tests/capture_service_runtime_entrypoint.spec.luau
.\scripts\run-tests.ps1
```
