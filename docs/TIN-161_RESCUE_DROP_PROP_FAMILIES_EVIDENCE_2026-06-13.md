# TIN-161 Rescue Drop Effects and Prop Families Evidence (2026-06-13)

## Issue

- ID: TIN-161 (follow-up slice)
- Scope: rescue-relevant drop effects, additional prop families, Studio spot-check checklist

## Shipped

- `DefensivePropState.EvaluateRescueDropEffect` for deterministic rescue-context evaluation (active contract or downed ally in zone).
- `DefensivePropService` grants rescue acceleration on qualifying drops via `_RescueContractService_QueryAPI.GrantRescueAcceleration`.
- `RescueContractService` query API symmetry: `GrantRescueAcceleration(userId, at)`.
- Prop-type timing overrides: shelf (6s active), rope_gate (1s stagger).
- Authored map anchors: `DefensiveProp_B` + `DefensivePropZone_B`, `DefensiveProp_C` + `DefensivePropZone_C`.
- Studio spot-check checklist: `docs/TIN-161_STUDIO_SPOTCHECK_CHECKLIST.md`.

## Boundary

- Rescue drop effect reuses existing rescue acceleration duration; no new rescue contract semantics.
- Authored-zone props only; no placement model or persistence changes.
- Studio spot-check checklist provided; live Play evidence deferred to manual validation.

## Validation

```powershell
.\scripts\run-validation.ps1 -ChangedOnly
lune run tests/defensive_prop_state.spec.luau
lune run tests/defensive_prop_service_runtime_entrypoint.spec.luau
.\scripts\run-tests.ps1
```
