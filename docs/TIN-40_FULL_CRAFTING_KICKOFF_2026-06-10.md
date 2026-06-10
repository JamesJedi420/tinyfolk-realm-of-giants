# TIN-40 Full Crafting System Kickoff (2026-06-10)

## Issue

- ID: TIN-40
- Title: Implement full crafting system
- Linear: https://linear.app/spectranoir/issue/TIN-40/implement-full-crafting-system
- Related: TIN-22 inventory/crafting foundation

## Scope

- Expand canonical item and recipe catalogs in `InventoryCraftConfig`.
- Add craft-chain recipes that consume prior crafted outputs.
- Add crafted-item consumption flow in shared state (`ConsumeItems`).
- Add craftable-recipe listing in shared state and service query API.
- Keep debug snapshot/attribute exposure for crafting state.
- Extend focused specs for new catalog and flows.

## Boundary

- Shared config/state and `InventoryCraftService` query/debug surfaces only.
- No persistence, final HUD/UX, equip/visual coupling, or construction/resource-flow spending.

## Risks

- Scope creep into economy sinks before recipe catalog is stable.
- Breaking canonical-catalog guard on public `_InventoryCraftService_QueryAPI.Craft`.

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
