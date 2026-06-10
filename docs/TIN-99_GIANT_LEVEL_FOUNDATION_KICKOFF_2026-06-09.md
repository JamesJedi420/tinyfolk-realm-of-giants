# TIN-99 Giant Level Foundation — Kickoff

**Date:** 2026-06-09  
**Issue:** [TIN-99](https://linear.app/spectranoir/issue/TIN-99/implement-giant-level-system)

## Slice boundary (foundation)

- `GiantLevelConfig` — XP awards by event kind, level threshold table, max level.
- `GiantLevelState` — pure `ApplyXpEvent`, `ResolveLevelFromXp`, idempotent by `operationId`.
- `GiantLevelService` — `_GiantLevelService_QueryAPI`, realm-owner attribute projection.
- Giant realm save root `giantLevelPersistence: { xp, level, recentEvents[] }`.
- Wire 3 XP producers: capture success, containment held (released/timeout), worksite upgrade success.
- Realm-owner debug attributes: `GiantXp`, `GiantLevel`, `GiantXpToNextLevel`.

## Deferred (remaining TIN-99 scope)

- Configurable level unlock catalog and gameplay modifiers.
- Level-up VFX / Studio polish.
- Cross-realm XP sync.
- Trades XP source.
- Board essence purchases (deprecated path).

## Validation

```powershell
lune run tests/giant_level_state.spec.luau
lune run tests/giant_level_service_runtime_entrypoint.spec.luau
lune run tests/giant_realm_save_schema.spec.luau
lune run tests/trophy_service_runtime_entrypoint.spec.luau
.\scripts\run-validation.ps1 -ChangedOnly
```
