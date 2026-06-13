# TIN-151 Anti-Guarding Containment Pressure Closure (2026-06-13)

## Issue

- ID: TIN-151
- Title: Implement anti-guarding containment pressure
- Date: 2026-06-13

## Shipped

- Added shared `AntiGuardingContainmentPressureState` for grace-window evaluation, proximity pressure accumulation/decay, and counterplay readiness.
- Extended `CaptureConfig` with anti-guarding tuning and readable target attributes (`AntiGuardingPressure`, `AntiGuardingPressurePhase`, `AntiGuardingCounterplayReady`).
- Added `AntiGuardingContainmentPressureService` heartbeat proximity tracking for `contained` custody records.
- Extended `CaptivityEscapeProgressState.ResolveAntiGuardingCounterplay` and `CaptivityEscapeService.ApplyAntiGuardingCounterplay` for bounded escape-progress release outcomes.

## Boundary

- Contained-phase sustained guarding only; no safe-zone immunity carve-outs.
- First counterplay outcome only: guaranteed escape-progress release (`released` custody end).
- Existing repeat-capture cooldown remains separate capture-request anti-farm logic.

## Validation

```powershell
.\scripts\run-validation.ps1 -ChangedOnly
lune run tests/anti_guarding_containment_pressure_state.spec.luau
lune run tests/anti_guarding_containment_pressure_service_runtime_entrypoint.spec.luau
lune run tests/captivity_escape_service_runtime_entrypoint.spec.luau
lune run tests/capture_service_runtime_entrypoint.spec.luau
.\scripts\run-tests.ps1
```

## Deferred

- Studio guarding loop spot-check.
- Additional counterplay outcomes: emergency route access, lock break, rescue-contract escalation.
