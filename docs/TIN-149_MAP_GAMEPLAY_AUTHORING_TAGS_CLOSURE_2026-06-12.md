# TIN-149 Map Gameplay Authoring Tags Closure (2026-06-12)

## Shipped

- Added `GameplayMapAuthoringConfig` with seven `GameplayTag_*` tags and collision/ownership mappings.
- Added `GameplayMapAuthoringResolver` with ancestor tag walk integrated into `GameplayCollisionGroupMatrix` and `GameplayPhysicsOwnershipPolicy`.
- Authored map tags on Pen, capture zones, granary/warehouse doors, containment dressing, trade-dock loot cluster, and containment pressure mass.
- Added `GameplayDoor` / `RewardLoot` attributes on warehouse door frame and trade-dock loot cluster.
- Added `tests/gameplay_map_authoring_resolver.spec.luau` and `tests/gameplay_map_authoring_coverage.spec.luau`.

## Validation

```powershell
.\scripts\run-validation.ps1 -ChangedOnly
lune run tests/gameplay_map_authoring_resolver.spec.luau
lune run tests/gameplay_map_authoring_coverage.spec.luau
lune run tests/gameplay_collision_group_matrix.spec.luau
lune run tests/gameplay_physics_ownership_policy.spec.luau
.\scripts\run-tests.ps1
rojo build default.project.json -o TinyfolkRealmOfGiants.rbxlx
```

All passed locally.

## Remaining scope

- Execute Studio runbook evidence table (manual).
- Runtime build-preview part tagging when preview ghosts exist.
- Snare trap BasePart ownership refresh when trap artifacts gain physical parts.
- Broader map folder tag pass beyond the six authored anchors in `RequiredTaggedRoots`.
