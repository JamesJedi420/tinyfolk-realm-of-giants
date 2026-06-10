# TIN-40 Full Crafting System Closure (2026-06-10)

## Issue

- ID: TIN-40
- Title: Implement full crafting system
- Linear: https://linear.app/spectranoir/issue/TIN-40/implement-full-crafting-system

## Shipped

- Expanded canonical item catalog to twelve entries (six materials, six crafted base/upgrade items).
- Expanded canonical recipe catalog to six recipes, including craft-chain upgrades from TIN-22 outputs.
- Added `InventoryCraftState.ConsumeItems` for crafted-item spend flows.
- Added `InventoryCraftState.ListCraftableRecipes` / `ListCraftableRecipeIds` for affordable recipe listing.
- Added `InventoryCraftConfig.ValidateItemCatalog` and `ValidateRecipeCatalog` cross-validation helpers.
- Extended `_InventoryCraftService_QueryAPI` with `ConsumeItems` and `ListCraftableRecipes`.
- Extended debug snapshot/attributes with `craftableRecipeIds` and `InventoryCraftableRecipeCount`.
- Preserved canonical-catalog guard on public `Craft` query API.

## Validation

- `.\scripts\run-validation.ps1 -ChangedOnly`
- `lune run tests/inventory_craft_state.spec.luau`
- `lune run tests/inventory_craft_service_runtime_entrypoint.spec.luau`
- `lune run tests/inventory_craft_config.spec.luau`
- `.\scripts\run-tests.ps1`

## Deferred

- Persistence and profile gateway integration.
- Final crafting UX polish.
- Specialist visual equip coupling.
- Inventory item grants from labor/resource-flow systems.
