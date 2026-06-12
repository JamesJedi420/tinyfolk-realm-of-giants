# TIN-149 Gameplay Collision Group Matrix Closure (2026-06-12)

## Shipped

- Added `GameplayCollisionGroupConfig` with ten gameplay collision groups and explicit collide/touch/ignore relation entries.
- Added pure `GameplayCollisionGroupMatrix` resolver for character profiles (role, custody, carry) and authored world parts (route attributes, trigger heuristics, containment district, explicit override attribute).
- Added `CollisionGroupService` module + server bootstrap registering the matrix via `PhysicsService` at startup.
- Assigns character collision groups on role/capture/carry attribute changes and `CharacterAdded`.
- Assigns world collision groups under `Workspace.Map` at startup.
- Exposed `_CollisionGroupService_QueryAPI` for tests/debug.

## Validation

```powershell
.\scripts\run-validation.ps1 -ChangedOnly
lune run tests/gameplay_collision_group_matrix.spec.luau
lune run tests/collision_group_service_runtime_entrypoint.spec.luau
.\scripts\run-tests.ps1
```

All passed locally.

## Studio evidence

- `docs/TIN-149_GAMEPLAY_COLLISION_GROUP_MATRIX_STUDIO_EVIDENCE_2026-06-12.md` — manual Play Solo / two-player spot-check runbook for tunnels, containment, grab/carry, escape pads, safe zones, and trigger volumes (includes TIN-150 ownership attribute checks).

## Remaining scope

- Execute the Studio runbook and fill the evidence table (manual).
- CollectionService tag authoring pass for map folders beyond attribute heuristics.
- Build preview part assignment when runtime preview parts exist.
