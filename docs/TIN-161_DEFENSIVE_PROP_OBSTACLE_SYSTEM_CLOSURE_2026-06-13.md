# TIN-161 Defensive Prop Obstacle System Closure (2026-06-13)

## Issue

- ID: TIN-161
- Title: Implement defensive prop obstacle system
- Date: 2026-06-13

## Shipped

- Added `DefensivePropConfig` with authored prop/zone conventions, barrier/break/reset timing, and prop-type catalog.
- Added shared `DefensivePropState` for Ready, Dropped, Blocked, Broken, Resetting, and Disabled lifecycle transitions plus Giant macro route block evaluation.
- Added `DefensivePropService` with Tinyfolk drop, Giant timed break start/complete, query API, and event-log hooks.
- Integrated Giant macro route blocking through `GiantBuildModeService` via `_DefensivePropService_QueryAPI`.
- Authored runtime anchors: `DefensiveProp_A` + `DefensivePropZone_A`.

## Boundary

- Authored-zone props only; no arbitrary placement or persistence.
- Asymmetric traversal: Tinyfolk drop pressure blocks zone-scoped Giant macro routes during active windows only.
- Startup barrier phase remains traversable; Giants retain timed break counterplay.
- Stagger/rescue side effects, portable props, and presentation polish remain deferred.

## Validation

```powershell
.\scripts\run-validation.ps1 -ChangedOnly
lune run tests/defensive_prop_state.spec.luau
lune run tests/defensive_prop_service_runtime_entrypoint.spec.luau
.\scripts\run-tests.ps1
```

## Deferred

- Live Studio Play spot-check evidence (checklist at `docs/TIN-161_STUDIO_SPOTCHECK_CHECKLIST.md`).
- Portable props and presentation polish.
