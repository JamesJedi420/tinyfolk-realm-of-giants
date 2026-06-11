# TIN-67 Trophy Display Preference Persistence Kickoff (2026-06-10)

## Boundary

Harden `trophyDisplayPreference` profile persistence so gateway load/clone sanitization and shared normalize/apply helpers match other TIN-67 profile fields.

## In scope

- Rename/extend `TrophyDisplayPolicyState` to `TrophyDisplayPolicyProfileState` with `HasPersistedState`, `GetPreference`, `CopyProfileField`, and `ApplyOptOut`.
- `ProfilePersistenceGateway` default clone and load sanitization for `trophyDisplayPreference`.
- `TrophyDisplayPolicyService` wired through shared profile-state helpers.
- Focused specs: `tests/trophy_display_policy_profile_state.spec.luau` and gateway sanitization coverage.

## Out of scope

- Skills, discovered realms, party history, pending recovery persistence.
- Cross-server transfer and load-failure routing.
- TIN-27/TIN-40 construction metal spend and crafting HUD polish.

## Validation plan

- `.\scripts\run-validation.ps1 -ChangedOnly`
- `lune run tests/trophy_display_policy_profile_state.spec.luau`
- `lune run tests/profile_persistence_gateway.spec.luau`
- `.\scripts\run-tests.ps1`
