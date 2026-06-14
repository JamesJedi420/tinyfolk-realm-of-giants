# TIN-61 Containment Structure System Kickoff (2026-06-14)

## Issue

- ID: TIN-61
- Title: Implement containment structure system
- Milestone: Capture, Rescue, and Routing
- Linear: https://linear.app/spectranoir/issue/TIN-61/implement-containment-structure-system

## Goal

Give Giants authored containment structures with capacity, escape interaction surfaces, and teammate rescue eligibility instead of phase-only containment records.

## In scope (this slice)

- `ContainmentStructureConfig` + shared `ContainmentStructureState` for capacity, occupants, escape/rescue eligibility.
- `ContainmentStructureService` with structure/zone registry, occupant assign/remove, and `_ContainmentStructureService_QueryAPI`.
- Wire `CaptureService.PromoteTargetToContained` to assign occupants when structures are registered; clear occupants on custody end.
- Authored anchors: `ContainmentStructure_A` (cage, capacity 2) + `ContainmentStructureZone_A` at Pen choke.
- Lune specs for shared state and runtime entrypoint.

## Out of scope / deferred

- Full structure family catalog and Giant build-mode placement.
- F-key client interaction wiring.
- Persistence across sessions.
- HUD/VFX/audio polish.

## Validation plan

```powershell
.\scripts\run-validation.ps1 -ChangedOnly
lune run tests/containment_structure_state.spec.luau
lune run tests/containment_structure_service_runtime_entrypoint.spec.luau
lune run tests/capture_service_runtime_entrypoint.spec.luau
lune run tests/captivity_duration_state.spec.luau
.\scripts\run-tests.ps1
```
