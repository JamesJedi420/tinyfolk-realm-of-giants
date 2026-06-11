# TIN-67 Tinyfolk Tool Loadout Persistence Closure (2026-06-10)

## Shipped

- Added `Shared/TinyfolkTools/TinyfolkToolLoadoutProfileState` with canonical loadout normalize/apply/copy helpers.
- Extended `ProfilePersistenceGateway` clone/copy and load sanitization to round-trip `tinyfolkToolLoadoutState` through the shared module.
- Updated `TinyfolkToolLoadoutState` to persist selections via the shared profile-state helpers.
- Added `tests/tinyfolk_tool_loadout_profile_state.spec.luau` and gateway load-sanitization coverage.

## Validation

- `.\scripts\run-validation.ps1 -ChangedOnly` — pass
- `lune run tests/tinyfolk_tool_loadout_profile_state.spec.luau` — pass
- `lune run tests/profile_persistence_gateway.spec.luau` — pass
- `.\scripts\run-tests.ps1` — pass

## Remaining TIN-67 scope

- Skills, discovered realms, party history, and pending recovery persistence.
- Cross-server transfer and load-failure routing.

## Studio follow-up

Select Tinyfolk tools, leave, rejoin, and confirm `tinyfolkToolLoadoutState` round-trips through profile load/save.
