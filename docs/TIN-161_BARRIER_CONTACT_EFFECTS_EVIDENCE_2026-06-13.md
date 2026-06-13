# TIN-161 Barrier Contact Effects Evidence (2026-06-13)

## Issue

- ID: TIN-161 (follow-up slice)
- Scope: Giant barrier contact stagger/interruption during active Blocked window

## Shipped

- `DefensivePropConfig` contact tuning: radius, stagger duration, cooldown, Giant heartbeat scan interval.
- `DefensivePropState.ApplyBarrierContact` / `CanApplyBarrierContact` / `InterruptBreak` for deterministic blocked-window contact and break cancellation.
- `DefensivePropService` Giant contact resolver, cooldown tracking, stagger player attributes, heartbeat scan, and `ResolveGiantBarrierContact` query API.
- `TinyfolkStatusService` query API symmetry: `SetConditionForUserId` (mirrors existing snare clear seam).

## Boundary

- Contact-based only (prop radius); no zone-wide instant stun.
- Active Blocked window only; startup Dropped phase unchanged.
- No new prop placement model or persistence.

## Validation

```powershell
.\scripts\run-validation.ps1 -ChangedOnly
lune run tests/defensive_prop_state.spec.luau
lune run tests/defensive_prop_service_runtime_entrypoint.spec.luau
lune run tests/tinyfolk_status_service_runtime_entrypoint.spec.luau
.\scripts\run-tests.ps1
```
