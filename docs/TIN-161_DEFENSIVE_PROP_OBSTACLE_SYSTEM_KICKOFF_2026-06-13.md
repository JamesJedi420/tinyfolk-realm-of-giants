# TIN-161 Defensive Prop Obstacle System Kickoff (2026-06-13)

## Issue

- ID: TIN-161
- Title: Implement defensive prop obstacle system
- Milestone: Capture, Rescue, and Routing

## Goal

Give Tinyfolk temporary terrain counterplay that buys time without guaranteeing safety.

## In scope (this slice)

- Authored-zone defensive prop anchors (`DefensiveProp_*`) with zone pairing (`DefensivePropZone_*`).
- Shared deterministic prop lifecycle in `DefensivePropState`: Ready, Dropped, Blocked, Broken, Resetting, Disabled.
- Server-authoritative Tinyfolk drop and Giant timed break/complete actions via `DefensivePropService`.
- Startup/active barrier timing before Giant macro route blocking; asymmetric traversal (Tinyfolk unaffected, Giants blocked or break).
- Giant macro route access integration through `_DefensivePropService_QueryAPI` and `GiantBuildModeService`.

## Out of scope / deferred

- Arbitrary wall placement, free prop placement, persistence, full HUD/VFX/audio polish.
- Portable props, infinite chained safe loops, default Giant bypass lanes.
- Stagger/rescue-drop side effects beyond route-pressure blocking in this slice.

## Validation plan

```powershell
.\scripts\run-validation.ps1 -ChangedOnly
lune run tests/defensive_prop_state.spec.luau
lune run tests/defensive_prop_service_runtime_entrypoint.spec.luau
lune run tests/giant_build_mode_service_runtime_entrypoint.spec.luau
.\scripts\run-tests.ps1
```
