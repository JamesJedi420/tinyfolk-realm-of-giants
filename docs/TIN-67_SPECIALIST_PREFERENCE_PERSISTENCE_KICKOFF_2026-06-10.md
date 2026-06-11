# TIN-67 Specialist Preference Persistence Kickoff (2026-06-10)

## Issue

- ID: TIN-67 (focused slice: specialist preference hardening)
- Title: Implement Tinyfolk persistent profile
- Linear: https://linear.app/spectranoir/issue/TIN-67/implement-tinyfolk-persistent-profile
- Related deferrals: TIN-27, TIN-40

## Scope

- Add `SpecialistPreferenceProfileState` for canonical specialist preference normalize/apply helpers.
- Extend `ProfilePersistenceGateway` clone/copy and load sanitization for `specialistPreference`.
- Wire `SpecialistAssignmentService` persist paths through the shared profile-state module.
- Add `tests/specialist_preference_profile_state.spec.luau` and gateway/runtime coverage.

## Boundary

- `specialistPreference` fields only (`specialistRole`, `assignedStationId`, `lastAssignedAt`).
- No cross-server transfer or load-failure routing.

## Validation

```powershell
.\scripts\run-validation.ps1 -ChangedOnly
lune run tests/specialist_preference_profile_state.spec.luau
lune run tests/specialist_assignment_service_runtime_entrypoint.spec.luau
lune run tests/profile_persistence_gateway.spec.luau
.\scripts\run-tests.ps1
```

## Deferred

- Safe location, tools, skills, escape records, discovered realms, party history, pending recovery.
- Crafting HUD polish, specialist equip coupling, construction metal spend.
