# TIN-67 Inventory Craft Persistence Closure (2026-06-10)

## Shipped

- Added `Shared/InventoryCraft/InventoryCraftProfileState` with canonical item-count normalize/apply helpers.
- Extended `ProfilePersistenceGateway` clone/copy to round-trip `inventoryCraftState` when present.
- Wired `InventoryCraftService` to hydrate from profile, bootstrap first-time Tinyfolk, and persist on inventory mutations and leave.
- Added `tests/inventory_craft_profile_state.spec.luau` and persistence coverage in inventory/gateway runtime specs.

## Validation

- `.\scripts\run-validation.ps1 -ChangedOnly` — pass
- `lune run tests/inventory_craft_profile_state.spec.luau` — pass
- `lune run tests/inventory_craft_service_runtime_entrypoint.spec.luau` — pass
- `lune run tests/profile_persistence_gateway.spec.luau` — pass
- `.\scripts\run-tests.ps1` — pass

## Remaining TIN-67 scope

- Tools, skills, escape records, discovered realms, party history, safe location, and pending recovery persistence.

## Studio follow-up

Rejoin after warehouse `iron_filings` grant to confirm persisted inventory counts.
