# TIN-101 Pen Rationing Starvation Consequences — Closure

**Date:** 2026-06-08  
**Parent:** [TIN-101](https://linear.app/spectranoir/issue/TIN-101)  
**Branch:** `tin-101-pen-rationing-starvation-consequences`

## Goal

Add pen-level rationing modifiers plus starvation consequences (morale loss and forced release).

## Shipped

- `VillageWorksiteUpgradeConfig` pen rationing food multipliers and starvation release thresholds by level.
- `VillageWorksiteUpgradeState.ResolvePenRationingModifiers` for pen upgrade effects.
- `PenRationingService` applies pen-level food cost scaling, tracks consecutive shortfall ticks, reduces custodian morale on shortfall, recovers morale on successful ration ticks, and forces `starvation` custody end on oldest captive when threshold is reached.
- `CaptureService` / `ContainmentRewardResolver` accept `starvation` end reason.

## Validation

```powershell
lune run tests/pen_rationing_state.spec.luau
lune run tests/pen_rationing_service_runtime_entrypoint.spec.luau
lune run tests/tin_food_pen_rationing_runtime_entrypoint.spec.luau
lune run tests/village_worksite_upgrade_state.spec.luau
.\scripts\run-validation.ps1 -ChangedOnly
```
