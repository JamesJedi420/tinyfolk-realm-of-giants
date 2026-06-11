# TIN-67 Trophy Display Preference Persistence Closure (2026-06-10)

## Shipped

- Renamed `TrophyDisplayPolicyState` to `TrophyDisplayPolicyProfileState` with canonical normalize/apply helpers (`HasPersistedState`, `GetPreference`, `CopyProfileField`, `ApplyOptOut`).
- Extended `ProfilePersistenceGateway` clone/copy and load sanitization to round-trip `trophyDisplayPreference` when present.
- Wired `TrophyDisplayPolicyService` persist paths through the shared profile-state module.
- Added `tests/trophy_display_policy_profile_state.spec.luau` and gateway/runtime coverage.

## Validation

- `.\scripts\run-validation.ps1 -ChangedOnly` — pass (after staging rename; deleted legacy module no longer targeted)
- `lune run tests/trophy_display_policy_profile_state.spec.luau` — pass
- `lune run tests/profile_persistence_gateway.spec.luau` — pass
- `lune run tests/trophy_display_policy_service_runtime_entrypoint.spec.luau` — pass
- `.\scripts\run-tests.ps1` — pass

## Remaining TIN-67 scope

- Skills, discovered realms, party history, and pending recovery persistence.
- Cross-server transfer and load-failure routing.

## Studio follow-up

Join as Tinyfolk, toggle trophy display opt-out (`O`), leave, rejoin, and confirm the preference restores from profile.
