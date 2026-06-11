# TIN-67 Inventory Craft Persistence Kickoff (2026-06-10)

## Issue

- ID: TIN-67 (focused slice: inventory craft material counts)
- Title: Implement Tinyfolk persistent profile
- Linear: https://linear.app/spectranoir/issue/TIN-67/implement-tinyfolk-persistent-profile
- Related deferrals: TIN-27, TIN-40

## Scope

- Add `InventoryCraftProfileState` for player-profile `inventoryCraftState.itemCounts`.
- Hydrate `InventoryCraftService` sessions from `ProfilePersistenceGateway` on ownership-ready.
- Persist item counts on grant, consume, craft, and player leave.
- Bootstrap first-time players with `TEST_STARTING_ITEMS` when no persisted inventory exists.
- Extend gateway clone/copy handling and focused specs.

## Boundary

- Tinyfolk craft material item counts only.
- No crafting HUD, equip/visual coupling, or construction metal spend.

## Validation

```powershell
.\scripts\run-validation.ps1 -ChangedOnly
lune run tests/inventory_craft_profile_state.spec.luau
lune run tests/inventory_craft_service_runtime_entrypoint.spec.luau
lune run tests/profile_persistence_gateway.spec.luau
.\scripts\run-tests.ps1
```

## Deferred

- Broader TIN-67 profile fields (tools, skills, escape records, safe location, recovery state).
- Crafting UX polish and specialist equip coupling.
- Construction metal spend.

## Studio check (TIN-27 regression)

Assign Miner → F at Forge_A (complete task) → haul → F at Warehouse_A → confirm `MetalStoredTotal` and `iron_filings` inventory grant; rejoin and confirm `iron_filings` count persists.
