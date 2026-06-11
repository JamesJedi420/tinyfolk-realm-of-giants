# TIN-67 Escape History Persistence Kickoff (2026-06-10)

## Issue

- ID: TIN-67 (focused slice: escape history hardening)
- Title: Implement Tinyfolk persistent profile
- Linear: https://linear.app/spectranoir/issue/TIN-67/implement-tinyfolk-persistent-profile
- Related deferrals: TIN-27, TIN-40

## Scope

- Add `EscapeHistoryProfileState` for canonical escape record normalize/append/copy helpers.
- Extend `ProfilePersistenceGateway` clone/copy and load sanitization for `escapeHistory`.
- Wire `EscapeOutcomeResolver` profile append paths through the shared profile-state module.
- Add `tests/escape_history_profile_state.spec.luau` and gateway/runtime coverage.

## Boundary

- Bounded `escapeHistory` records only (dedupe by `operationId`, default limit 25).
- No cross-server transfer or load-failure routing.

## Validation

```powershell
.\scripts\run-validation.ps1 -ChangedOnly
lune run tests/escape_history_profile_state.spec.luau
lune run tests/escape_outcome_resolver.spec.luau
lune run tests/profile_persistence_gateway.spec.luau
.\scripts\run-tests.ps1
```

## Deferred

- Safe location, tools, skills, discovered realms, party history, pending recovery.
- Crafting HUD polish, specialist equip coupling, construction metal spend.

## Studio follow-up

Escape via final exit, leave, rejoin, and confirm bounded `escapeHistory` round-trips through profile load/save.
