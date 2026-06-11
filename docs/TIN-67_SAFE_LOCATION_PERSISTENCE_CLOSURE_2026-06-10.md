# TIN-67 Safe Location Persistence Closure (2026-06-10)

## Shipped

- Added `Shared/Escape/SafeLocationProfileState` with canonical safe-return snapshot normalize/apply/copy helpers.
- Extended `ProfilePersistenceGateway` clone/copy and load sanitization to round-trip `safeLocation` when present.
- Wired `EscapeOutcomeResolver` to persist `escape_success` safe-location snapshots after successful hub return.
- Wired `EscapeService` transport `safe_return` relocation paths through the shared profile-state module.
- Added `tests/safe_location_profile_state.spec.luau` and gateway/runtime coverage updates.

## Validation

- `.\scripts\run-validation.ps1 -ChangedOnly` — pass
- `lune run tests/safe_location_profile_state.spec.luau` — pass
- `lune run tests/profile_persistence_gateway.spec.luau` — pass
- `.\scripts\run-tests.ps1` — pass

## Remaining TIN-67 scope

- Tools, skills, discovered realms, party history, and pending recovery persistence.
- Cross-server transfer and load-failure routing.

## Studio follow-up

Trigger transport safe-return and route escape, leave, rejoin, and confirm `safeLocation` round-trips through profile load/save.
