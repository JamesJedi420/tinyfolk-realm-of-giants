# TIN-67 Safe Location Persistence Kickoff (2026-06-10)

## Issue

- ID: TIN-67 (focused slice: safe location hardening)
- Title: Implement Tinyfolk persistent profile
- Linear: https://linear.app/spectranoir/issue/TIN-67/implement-tinyfolk-persistent-profile
- Related deferrals: TIN-27, TIN-40

## Scope

- Add `SafeLocationProfileState` for canonical safe-return snapshot normalize/apply/copy helpers.
- Extend `ProfilePersistenceGateway` clone/copy and load sanitization for `safeLocation`.
- Wire `EscapeOutcomeResolver` and `EscapeService` safe-return relocation paths through the shared profile-state module.
- Add `tests/safe_location_profile_state.spec.luau` and gateway/runtime coverage.

## Boundary

- Bounded `safeLocation` snapshot only (`returnPointName`, `returnedAt`, `returnReason`, optional realm/source context).
- No cross-server transfer or load-failure routing.

## Validation

```powershell
.\scripts\run-validation.ps1 -ChangedOnly
lune run tests/safe_location_profile_state.spec.luau
lune run tests/profile_persistence_gateway.spec.luau
.\scripts\run-tests.ps1
```

## Deferred

- Tools, skills, discovered realms, party history, pending recovery.
- Crafting HUD polish, specialist equip coupling, construction metal spend.

## Studio follow-up

Trigger transport safe-return and route escape, leave, rejoin, and confirm `safeLocation` round-trips through profile load/save.
