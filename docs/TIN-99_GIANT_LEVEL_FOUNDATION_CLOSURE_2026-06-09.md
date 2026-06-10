# TIN-99 Giant Level Foundation — Closure

**Date:** 2026-06-09  
**Issue:** [TIN-99](https://linear.app/spectranoir/issue/TIN-99/implement-giant-level-system)  
**Follow-up:** [TIN-241](https://linear.app/spectranoir/issue/TIN-241/giant-level-cross-realm-xp-sync-and-trade-xp-source)

## Shipped (prototype boundary)

### Foundation (PR #27)
- `GiantLevelConfig`, `GiantLevelState`, `GiantLevelService` — idempotent XP grants, level thresholds, realm-owner attributes.
- `giantLevelPersistence` on giant-realm save root with schema validation and GiantBuildMode save/apply.
- XP producers: capture success (+25), containment held/released/timeout (+40), worksite upgrade (+15).
- Session score vs persisted Giant level documented in `GAME_SPEC.md`.

### Unlock/modifier slice (PR #28)
- Configurable `LevelUnlockCatalog` with xp/containment reward modifiers.
- Explicit unlock resolution on level-up + legacy-save entitlement reconcile (`resolvedUnlockIds`; modifiers never inferred from raw level alone).
- Modifier query seam, realm-owner attribute projection, level-up signal attributes.
- Containment resource awards respect `containmentRewardMultiplier`.
- Optional `GiantLevelUpFeedbackClient` overlay.

## Re-scoped (deferred to TIN-241)

| Item | Reason deferred |
|------|-----------------|
| Cross-realm XP sync | Requires cross-server realm ownership / handoff architecture (`TIN-49`, `TIN-106`, `TIN-11`) |
| Trades XP source | Trade between Giant realms is future scope; needs `TIN-29` conversion seam |
| Board essence purchases | Deprecated by TIN-240 C2b — no action |

## Validation

```powershell
lune run tests/giant_level_state.spec.luau
lune run tests/giant_level_service_runtime_entrypoint.spec.luau
lune run tests/giant_realm_save_schema.spec.luau
.\scripts\run-validation.ps1 -ChangedOnly
```

All pass on master as of 2026-06-09.
