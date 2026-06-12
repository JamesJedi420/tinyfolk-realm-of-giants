# TIN-149 Map Gameplay Authoring Tags Kickoff (2026-06-12)

## Issue

- ID: TIN-149 (deferred follow-up)
- Title: CollectionService tag authoring pass for gameplay collision/ownership map surfaces
- Linear: https://linear.app/spectranoir/issue/TIN-149/implement-gameplay-collision-group-matrix

## Goal

Author gameplay-critical map folders/parts with CollectionService tags and explicit door/loot attributes so collision group and physics ownership resolvers no longer rely only on touch/district heuristics.

## Scope

- Add `GameplayMapAuthoringConfig` tag vocabulary and collision/ownership mappings.
- Add `GameplayMapAuthoringResolver` with ancestor tag walk used by collision and ownership world-part resolvers.
- Tag representative map roots: Pen/containment, capture trigger zone, granary/warehouse doors, trade-dock reward loot cluster, containment dressing.
- Add `GameplayDoor` / `RewardLoot` attributes where authored tags alone are insufficient for tests.
- Add coverage spec validating required tags in layout JSON.

## Boundary

- No runtime build-preview part assignment (still deferred until preview parts exist).
- No snare-trap BasePart refresh hook (folder-only artifacts remain).
- Visual-only dressing without gameplay tags remains unchanged unless within containment/door/loot authoring anchors.

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
