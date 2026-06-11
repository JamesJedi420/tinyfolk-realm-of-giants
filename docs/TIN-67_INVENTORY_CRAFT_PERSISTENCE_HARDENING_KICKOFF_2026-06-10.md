# TIN-67 Inventory Craft Persistence Hardening Kickoff (2026-06-10)

## Issue

- ID: TIN-67 (focused slice: inventory craft gateway hardening)
- Title: Implement Tinyfolk persistent profile
- Linear: https://linear.app/spectranoir/issue/TIN-67/implement-tinyfolk-persistent-profile

## Scope

- Add `CopyProfileField` and canonical persisted-state normalization to `InventoryCraftProfileState`.
- Route `ProfilePersistenceGateway` clone/copy and load sanitization through the shared module.
- Extend focused profile-state and gateway sanitization specs.

## Boundary

- `inventoryCraftState.itemCounts` hardening only.
- No crafting HUD, equip/visual coupling, or construction metal spend.

## Validation

```powershell
.\scripts\run-validation.ps1 -ChangedOnly
lune run tests/inventory_craft_profile_state.spec.luau
lune run tests/profile_persistence_gateway.spec.luau
.\scripts\run-tests.ps1
```

## Deferred

- Skills, discovered realms, party history, and pending recovery persistence.
- Cross-server transfer and load-failure routing.
