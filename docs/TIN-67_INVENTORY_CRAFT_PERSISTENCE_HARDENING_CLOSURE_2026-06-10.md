# TIN-67 Inventory Craft Persistence Hardening Closure (2026-06-10)

## Shipped

- Added `CopyProfileField` and canonical persisted-state normalization to `InventoryCraftProfileState`.
- Routed `ProfilePersistenceGateway` clone/copy and load sanitization through the shared module.
- Extended `tests/inventory_craft_profile_state.spec.luau` and gateway load-sanitization coverage.

## Validation

- `.\scripts\run-validation.ps1 -ChangedOnly` — pass
- `lune run tests/inventory_craft_profile_state.spec.luau` — pass
- `lune run tests/profile_persistence_gateway.spec.luau` — pass
- `.\scripts\run-tests.ps1` — pass

## Remaining TIN-67 scope

- Skills, discovered realms, party history, and pending recovery persistence.
- Cross-server transfer and load-failure routing.

## Studio follow-up

Rejoin after warehouse `iron_filings` grant to confirm sanitized `inventoryCraftState` round-trips through profile load/save.
