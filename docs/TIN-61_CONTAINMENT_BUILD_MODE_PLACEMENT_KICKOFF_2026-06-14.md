# TIN-61 / TIN-87 Containment Build-Mode Placement Kickoff (2026-06-14)

## Issue

- Follow-up to TIN-61 / TIN-87 deferred scope
- Linear: https://linear.app/spectranoir/issue/TIN-61/implement-containment-structure-system

## Goal

Wire Giant build-mode containment placements into `ContainmentStructureService` registry so placed cages/jars participate in delivery, escape, and rescue checks.

## In scope (this slice)

- `ContainmentStructureConfig.BuildModePlacements` + `GiantStructureCatalog` containment entries (`GiantStructure_Containment_Cage_A`, `GiantStructure_Containment_Jar_A`).
- Pure `ContainmentStructurePlacementState` for placement geometry/id resolution.
- `GiantBuildModeService` materializes `ContainmentStructure_*` + `ContainmentStructureZone_*` parts and refreshes containment registry.
- `ContainmentStructureService.RefreshRegistries` query seam.

## Out of scope / deferred

- Persistence across sessions / realm save replay for containment placements.
- HUD/VFX polish and additional structure families beyond two catalog entries.
- Build-mode zone radius tuning beyond config defaults.

## Validation plan

```powershell
.\scripts\run-validation.ps1 -ChangedOnly
lune run tests/containment_structure_placement_state.spec.luau
lune run tests/containment_structure_build_mode_placement.spec.luau
lune run tests/containment_structure_service_runtime_entrypoint.spec.luau
lune run tests/giant_build_mode_service_runtime_entrypoint.spec.luau
.\scripts\run-tests.ps1
```
