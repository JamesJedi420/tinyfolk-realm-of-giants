# TIN-151 Anti-Guarding Containment Pressure Kickoff (2026-06-13)

## Issue

- ID: TIN-151
- Title: Implement anti-guarding containment pressure
- Milestone: Capture, Rescue, and Routing
- Linear: https://linear.app/spectranoir/issue/TIN-151/implement-anti-guarding-containment-pressure

## Goal

Discourage Giants from camping over a contained Tinyfolk by accumulating server-owned proximity pressure after a post-placement grace window and resolving bounded counterplay when pressure maxes.

## Scope

- Add shared `AntiGuardingContainmentPressureState` for grace-window evaluation, proximity pressure accumulation/decay, and counterplay readiness.
- Extend `CaptureConfig` with anti-guarding tuning and readable attribute names.
- Add `AntiGuardingContainmentPressureService` heartbeat proximity tracking for `contained` custody records.
- Extend `CaptivityEscapeProgressState` + `CaptivityEscapeService` with `ApplyAntiGuardingCounterplay` escape-progress release outcome.
- Project `AntiGuardingPressure`, `AntiGuardingPressurePhase`, and `AntiGuardingCounterplayReady` on contained targets.

## Boundary

- Contained-phase sustained guarding only; no safe-zone immunity carve-outs.
- First counterplay outcome: guaranteed escape-progress release (`released` custody end).
- Deferred: emergency route access, lock break, rescue-contract escalation outcomes, Studio guarding loop spot-check.
- Existing repeat-capture cooldown (`anti_guarding_repeat_target_cooldown`) remains separate capture-request anti-farm logic.

## Validation

```powershell
.\scripts\run-validation.ps1 -ChangedOnly
lune run tests/anti_guarding_containment_pressure_state.spec.luau
lune run tests/anti_guarding_containment_pressure_service_runtime_entrypoint.spec.luau
lune run tests/captivity_escape_service_runtime_entrypoint.spec.luau
lune run tests/capture_service_runtime_entrypoint.spec.luau
.\scripts\run-tests.ps1
```
