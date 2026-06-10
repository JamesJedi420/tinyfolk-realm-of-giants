# TIN-27 Metal Production and Advanced Material Flow Closure (2026-06-10)

## Issue

- ID: TIN-27
- Title: Implement metal production and advanced material flow
- Linear: https://linear.app/spectranoir/issue/TIN-27/implement-metal-production-and-advanced-material-flow

## Shipped

- Added `Metal` to session `ResourceFlowState` with produced/in-transit/stored flow and debug attributes.
- Added `Forge_A` station asset and config (`ForgeNamePrefix`, refine labor action, stone cost per refine tick).
- Miner `refine` at `Forge_A` spends stored Stone and produces Metal into the station produced pool.
- Extended warehouse delivery to store in-transit Metal and grant inventory craft materials via `AdvancedMaterialFlowState`.
- Added `_InventoryCraftService_QueryAPI.GrantItems` for session inventory grants from economy delivery.
- Added focused specs for advanced material grants, metal flow, forge→warehouse E2E, and warehousing harness updates.

## Flow contract

| Step | Actor | Surface | Effect |
|------|-------|---------|--------|
| Refine | Miner @ Forge_A | F task complete | stored Stone spent → Metal produced pool increases |
| Haul | Any Tinyfolk @ Forge_A | F pickup | produced → in-transit |
| Store | Any Tinyfolk @ Warehouse_A | F deliver | in-transit → stored; grants `iron_filings` to deliverer |
| Store (Stone) | Any Tinyfolk @ Warehouse_A | F deliver | in-transit Stone → stored; grants `stone_shard` per configured units |

## Validation

- `.\scripts\run-validation.ps1 -ChangedOnly`
- `lune run tests/advanced_material_flow_state.spec.luau`
- `lune run tests/resource_flow_metal.spec.luau`
- `lune run tests/tin_metal_forge_warehouse_runtime_entrypoint.spec.luau`
- `lune run tests/station_service_runtime_entrypoint.spec.luau`
- `lune run tests/warehousing_service_runtime_entrypoint.spec.luau`
- `lune run tests/inventory_craft_service_runtime_entrypoint.spec.luau`
- `.\scripts\run-tests.ps1`

## Deferred

- Inventory persistence via `ProfilePersistenceGateway`.
- Crafting UX polish and specialist equip/visual coupling.
- Construction metal spend and treasury HUD metal projection.
