# TIN-67 Escape History Persistence Closure (2026-06-10)

## Shipped

- Added `Shared/Escape/EscapeHistoryProfileState` with canonical escape record normalize/append/copy helpers.
- Extended `ProfilePersistenceGateway` clone/copy and load sanitization to round-trip `escapeHistory` when present.
- Wired `EscapeOutcomeResolver` profile append paths through the shared profile-state module.
- Added `tests/escape_history_profile_state.spec.luau` and gateway/runtime coverage.

## Validation

- `.\scripts\run-validation.ps1 -ChangedOnly` — pass
- `lune run tests/escape_history_profile_state.spec.luau` — pass
- `lune run tests/escape_outcome_resolver.spec.luau` — pass
- `lune run tests/profile_persistence_gateway.spec.luau` — pass
- `.\scripts\run-tests.ps1` — pass

## Remaining TIN-67 scope

- Safe location, tools, skills, discovered realms, party history, and pending recovery persistence.
- Cross-server transfer and load-failure routing.

## Studio follow-up

Escape via final exit, leave, rejoin, and confirm bounded `escapeHistory` round-trips through profile load/save.
