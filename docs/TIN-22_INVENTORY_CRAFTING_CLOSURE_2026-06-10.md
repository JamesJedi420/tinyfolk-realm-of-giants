# TIN-22 Inventory and Crafting Foundation Closure (2026-06-10)

## Issue

- ID: TIN-22
- Title: Implement inventory and crafting foundation

## Shipped

- Server-owned Tinyfolk session inventory state in `InventoryCraftState`.
- Minimal crafting input/output model with canonical item and recipe catalogs in `InventoryCraftConfig`.
- Small crafted-item set: `twine_satchel`, `repair_wedge` from material inputs.
- Runtime orchestration and debug exposure in `InventoryCraftService` via query API, player attributes, and debug remotes.

## Validation

- `.\scripts\run-validation.ps1 -ChangedOnly`
- `lune run tests/inventory_craft_state.spec.luau`
- `lune run tests/inventory_craft_service_runtime_entrypoint.spec.luau`
- `.\scripts\run-tests.ps1`

## Deferred

- Persistence
- Full recipe catalog and item variety (TIN-40 context)
- Final UX polish
- Specialist visual equip coupling
