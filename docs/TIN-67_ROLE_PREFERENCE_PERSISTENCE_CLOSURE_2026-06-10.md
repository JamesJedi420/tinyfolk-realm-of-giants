# TIN-67 Role Preference Persistence Closure (2026-06-10)

## Shipped

- Added `Shared/Role/RolePreferenceProfileState` with canonical role preference normalize/apply helpers.
- Extended `ProfilePersistenceGateway` clone/copy and load sanitization to round-trip `rolePreference` when present.
- Wired `RoleService` persist paths through the shared profile-state module.
- Added `tests/role_preference_profile_state.spec.luau` and gateway/runtime coverage.

## Validation

- `.\scripts\run-validation.ps1 -ChangedOnly` — pass
- `lune run tests/role_preference_profile_state.spec.luau` — pass
- `lune run tests/role_service_runtime_entrypoint.spec.luau` — pass
- `lune run tests/profile_persistence_gateway.spec.luau` — pass
- `.\scripts\run-tests.ps1` — pass

## Remaining TIN-67 scope

- Tools, skills, escape records, discovered realms, party history, safe location, and pending recovery persistence.
- Cross-server transfer and load-failure routing.

## Studio follow-up

Select Giant or Tinyfolk role, leave, rejoin, and confirm `SelectedRole` restores from profile.
