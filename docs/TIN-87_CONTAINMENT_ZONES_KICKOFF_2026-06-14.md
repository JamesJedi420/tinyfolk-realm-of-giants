# TIN-87 Containment Zones Kickoff (2026-06-14)

## Issue

- ID: TIN-87
- Title: Implement containment zones
- Milestone: Capture, Rescue, and Routing
- Linear: https://linear.app/spectranoir/issue/TIN-87/implement-containment-zones

## Goal

Complete the playable contained loop on top of TIN-61 structure registry: grab-place delivery, contained escape, and teammate structure rescue.

## In scope (slice 1)

- `ContainmentZoneEscapeState` for contained structure escape progress.
- `ContainmentZoneInteractionService` with grab-place delivery, contained escape (`F`), and structure rescue (`R`).
- `ContainmentStructureService.EvaluateCaptureDeliveryEligibility` read-only delivery gate.
- `CaptureService` projects `CaptureContainmentPhase` for client routing.
- `GrabService` place hook calls `TryDeliverGrabPlacement`.
- `ContainmentZoneInteractionClient` + `CaptivityEscapeClient` phase split for F/R keys.
- Escape actions: `contained_escape`, `structure_rescue`.

## Out of scope / deferred

- Full containment zone catalog beyond authored structure A.
- Build-mode placement and persistence.
- HUD/VFX/audio polish.
- Score-over-time tuning beyond existing containment reward resolver.

## Validation plan

```powershell
.\scripts\run-validation.ps1 -ChangedOnly
lune run tests/containment_zone_escape_state.spec.luau
lune run tests/containment_zone_interaction_service_runtime_entrypoint.spec.luau
lune run tests/containment_structure_service_runtime_entrypoint.spec.luau
lune run tests/capture_service_runtime_entrypoint.spec.luau
lune run tests/captivity_escape_service_runtime_entrypoint.spec.luau
.\scripts\run-tests.ps1
```
