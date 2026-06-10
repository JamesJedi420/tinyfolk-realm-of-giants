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

## Deferred (re-scoped to TIN-241)

- Cross-realm XP sync → [TIN-241](https://linear.app/spectranoir/issue/TIN-241/giant-level-cross-realm-xp-sync-and-trade-xp-source) (blocked on `TIN-49`/`TIN-106`/`TIN-11`).
- Trades XP source → TIN-241 (blocked on `TIN-29`).
- Board essence purchases (deprecated path; retired by TIN-240 C2b).

Closure: `docs/TIN-99_GIANT_LEVEL_FOUNDATION_CLOSURE_2026-06-09.md`

## Completed in unlock/modifier slice

- Configurable level unlock catalog (`GiantLevelConfig.LevelUnlockCatalog`) with gameplay modifiers.
- Explicit unlock resolution on level-up and legacy-save entitlement reconcile (no retroactive modifier inflation from raw level alone).
- Realm-owner modifier attributes and `GetModifierSnapshot` query seam.
- Optional Giant level-up feedback client overlay (`GiantLevelUpFeedbackClient`).

## Validation

```powershell
lune run tests/giant_level_state.spec.luau
lune run tests/giant_level_service_runtime_entrypoint.spec.luau
lune run tests/giant_realm_save_schema.spec.luau
lune run tests/trophy_service_runtime_entrypoint.spec.luau
.\scripts\run-validation.ps1 -ChangedOnly
```
