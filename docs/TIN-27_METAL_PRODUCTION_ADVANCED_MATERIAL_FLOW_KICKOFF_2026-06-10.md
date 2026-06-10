# TIN-27 Metal Production and Advanced Material Flow Kickoff (2026-06-10)

## Issue

- ID: TIN-27
- Title: Implement metal production and advanced material flow
- Linear: https://linear.app/spectranoir/issue/TIN-27/implement-metal-production-and-advanced-material-flow

## Scope

- Add `Metal` to session `ResourceFlowState` (produced → in-transit → stored).
- Add `Forge_A` station: Miner refines stored Stone into Metal produced pool.
- Haul/deliver Metal through existing warehouse path.
- Grant inventory craft materials on warehouse delivery (`iron_filings` from Metal; `stone_shard` from Stone).
- Expose Metal flow attributes on warehouse/station debug surfaces.

## Boundary

- Session economy and inventory craft grants only.
- No persistence, crafting HUD polish, or construction metal spend in this slice.

## Key files

- `src/ReplicatedStorage/Shared/Config/AdvancedMaterialFlowConfig.luau`
- `src/ReplicatedStorage/Shared/GiantRealm/AdvancedMaterialFlowState.luau`
- `src/ReplicatedStorage/Shared/Config/StationConfig.luau`
- `src/ReplicatedStorage/Shared/Config/LaborActionConfig.luau`
- `src/ServerScriptService/Services/ResourceFlowState.luau`
- `src/ServerScriptService/Services/StationService.server.luau`
- `src/ServerScriptService/Services/WarehousingService.server.luau`
- `src/ServerScriptService/Services/InventoryCraftService.server.luau`
- `src/Workspace/Map/Stations/Forge/Layout.model.json`

## Validation

```powershell
.\scripts\run-validation.ps1 -ChangedOnly
lune run tests/advanced_material_flow_state.spec.luau
lune run tests/resource_flow_metal.spec.luau
lune run tests/tin_metal_forge_warehouse_runtime_entrypoint.spec.luau
lune run tests/station_service_runtime_entrypoint.spec.luau
lune run tests/warehousing_service_runtime_entrypoint.spec.luau
lune run tests/inventory_craft_service_runtime_entrypoint.spec.luau
.\scripts\run-tests.ps1
```

## Deferred

- Inventory persistence via `ProfilePersistenceGateway`.
- Crafting UX polish and specialist equip/visual coupling.
- Construction metal spend and treasury HUD metal projection.
