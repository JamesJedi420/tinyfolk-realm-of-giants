# TIN-161 Rescue Drop Effects and Prop Families Kickoff (2026-06-13)

## Issue

- ID: TIN-161
- Title: Implement defensive prop obstacle system
- Milestone: Capture, Rescue, and Routing

## Goal

Close remaining TIN-161 deferred scope: rescue-relevant drop side effects, additional authored prop families, and Studio spot-check evidence.

## In scope (this slice)

- Rescue-relevant drop effect: when a Tinyfolk drops a prop while rescuing (active contract) or with a downed ally in the prop zone, grant rescue acceleration via `_RescueContractService_QueryAPI.GrantRescueAcceleration`.
- Prop-type timing overrides in `DefensivePropConfig.PropTypes` (shelf longer active window, rope_gate longer stagger).
- Authored anchors `DefensiveProp_B` (shelf) and `DefensiveProp_C` (rope_gate) with paired zones on Giant macro route choke points.
- Studio drop/break/barrier spot-check checklist and evidence doc.

## Out of scope / deferred

- Arbitrary placement, persistence, portable props, full HUD/VFX/audio polish.
- Infinite chained safe loops or default Giant bypass lanes.

## Validation plan

```powershell
.\scripts\run-validation.ps1 -ChangedOnly
lune run tests/defensive_prop_state.spec.luau
lune run tests/defensive_prop_service_runtime_entrypoint.spec.luau
.\scripts\run-tests.ps1
```
