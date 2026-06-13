# TIN-73 Maximum Captivity Duration Closure (2026-06-13)

## Issue

- ID: TIN-73
- Title: Implement maximum captivity duration
- Linear: https://linear.app/spectranoir/issue/TIN-73/implement-maximum-captivity-duration

## Shipped

- Added shared `CaptivityDurationState` for captured/contained deadline evaluation, transfer anchor preservation, and timeout → `safe_return` fallback mapping.
- Extended `CaptureState` records with `captivityAnchorAt`, `containmentPhase`, `containedAt`, plus `ResolvePromoteToContained` and `ResolveTransferCustody`.
- Wired `CaptureService` timeout pruning to `CaptivityDurationState` and `CaptivitySafeReturnCaller`; added query seams for promote/transfer and captivity rules export.
- Added `EscapeService.ApplyCaptivitySafeReturn` query seam for relocation + safe-location profile recording.
- Extended `CaptureConfig` with explicit `MaxCapturedDurationSeconds` and `MaxContainedDurationSeconds`.

## Boundary

- No Giant-to-Giant custody transfer UX (TIN-71); transfer rules + query seam only.
- No containment structure placement system (TIN-61); contained phase is record transition only.
- No profile persistence of active captivity runtime.

## Validation

```powershell
.\scripts\run-validation.ps1 -ChangedOnly
lune run tests/captivity_duration_state.spec.luau
lune run tests/capture_state.spec.luau
lune run tests/capture_service_runtime_entrypoint.spec.luau
.\scripts\run-tests.ps1
```

## Deferred

- Studio spot-check for timeout → safe-return relocation in live map layout.
- Full custody-transfer gameplay flow and containment-structure delivery promotion hooks.
