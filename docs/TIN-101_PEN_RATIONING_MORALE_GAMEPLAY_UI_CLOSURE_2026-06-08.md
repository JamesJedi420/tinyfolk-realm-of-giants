# TIN-101 Pen Rationing Morale Gameplay + UI — Closure

**Date:** 2026-06-08  
**Parent:** [TIN-101](https://linear.app/spectranoir/issue/TIN-101)  
**Branch:** `tin-101-pen-rationing-morale-gameplay-ui`

## Goal

Extend pen rationing beyond server attributes: morale affects capture success, captives accumulate starvation exposure during shortfall, and clients surface rationing/morale feedback.

## Shipped

- `PenRationingState` morale capture gate (`ResolveCaptureMoraleCheck`, `ComputeCaptureReadinessPercent`) and captive shortfall streak helpers.
- `PenRationingConfig` morale capture sure threshold (50) and captive starving streak threshold (2); captive player attributes `PenRationingCaptiveShortfallStreak`, `PenRationingCaptiveStarving`.
- `CaptureService` blocks capture when custodian morale is depleted or fails a deterministic low-morale roll (`custodian_morale_depleted`, `custodian_morale_shaken`).
- `PenRationingService` increments/resets captive shortfall streaks on ration ticks and projects captive starvation attributes; clears on release.
- `PenRationingHudPresentation` + `PenRationingHudClient` show Giant pen morale/shortfall/capture readiness and Tinyfolk captive ration stress while held.

## Validation

```powershell
lune run tests/pen_rationing_state.spec.luau
lune run tests/pen_rationing_service_runtime_entrypoint.spec.luau
lune run tests/capture_service_runtime_entrypoint.spec.luau
lune run tests/pen_rationing_hud_presentation.spec.luau
.\scripts\run-validation.ps1 -ChangedOnly
```
