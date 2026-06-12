# TIN-149 Gameplay Collision Group Matrix Kickoff (2026-06-12)

## Issue

- ID: TIN-149
- Title: Implement gameplay collision group matrix
- Milestone: Capture, Rescue, and Routing
- Linear: https://linear.app/spectranoir/issue/TIN-149/implement-gameplay-collision-group-matrix

## Goal

Make Giant/Tinyfolk physical interactions predictable through one explicit gameplay collision matrix registered at server startup.

## Scope

- Add `GameplayCollisionGroupConfig` with ten gameplay groups and explicit collide/touch/ignore relations.
- Add pure `GameplayCollisionGroupMatrix` resolver for character profiles and authored world parts.
- Add `CollisionGroupService` to register the matrix via `PhysicsService` and assign groups to:
  - character parts on role/capture/carry attribute changes
  - `Workspace.Map` parts using attribute heuristics (`TinyfolkOnlyRoute`, trigger touch zones, containment district, explicit override)
- Expose `_CollisionGroupService_QueryAPI` for tests and debug.

## Groups

| Group | Purpose |
|-------|---------|
| `Gameplay_Giant` | Giant player characters |
| `Gameplay_Tinyfolk` | Tinyfolk player characters |
| `Gameplay_CarriedTinyfolk` | Physically carried Tinyfolk |
| `Gameplay_ContainedTinyfolk` | Custody-contained Tinyfolk |
| `Gameplay_GiantRoute` | Giant-only route geometry |
| `Gameplay_TinyfolkRoute` | Tinyfolk-only route geometry |
| `Gameplay_TriggerZone` | Non-colliding touch trigger volumes |
| `Gameplay_BuildPreview` | Build preview ghosts |
| `Gameplay_Containment` | Pen/containment structures |
| `Gameplay_WorldGeometry` | Default map collision |

## Boundary

- No client collision edits.
- No trigger event authority changes (touch vs ignore documented only).
- TIN-150 physics ownership policy deferred.
- Studio matrix spot-check runbook deferred to closure evidence.

## Validation

```powershell
.\scripts\run-validation.ps1 -ChangedOnly
lune run tests/gameplay_collision_group_matrix.spec.luau
lune run tests/collision_group_service_runtime_entrypoint.spec.luau
.\scripts\run-tests.ps1
```

## Deferred

- Per-part CollectionService tag authoring pass across all map folders.
- Build preview part assignment when Giant build preview parts exist at runtime.
- Studio verification checklist for tunnels, cages, grab zones, escape pads, safe zones.
