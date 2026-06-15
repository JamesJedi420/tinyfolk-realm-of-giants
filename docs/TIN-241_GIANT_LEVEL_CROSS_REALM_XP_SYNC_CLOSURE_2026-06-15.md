# TIN-241 Giant Level Cross-Realm XP Sync — Closure

**Date:** 2026-06-15  
**Issue:** [TIN-241](https://linear.app/spectranoir/issue/TIN-241/giant-level-cross-realm-xp-sync-and-trade-xp-source)

## Shipped

- `GiantLevelCrossRealmSyncState` — pending buffer encode/decode, idempotent merge/replay onto persisted realm level state.
- `GiantLevelPendingXpStore` + `MemoryStoreStructurePolicy.giantLevelPendingXp` — cross-server pending XP buffer keyed by `realmId`.
- `GiantLevelService` — publish on grant, merge on load, ack on save; `RecordTradeSuccess` for source/destination realm owners.
- `GiantLevelTradeXpProducer` + `ProfileTeleportHandoffService` trade confirm hook.
- `GiantLevelConfig.EventKinds.TradeSuccess` (+30 XP).

## Acceptance criteria

| Criterion | Result |
|---|---|
| Giant level survives cross-server entry/exit without duplicate XP | PASS — pending buffer merge + operationId dedup |
| Trade completion grants XP via GiantLevelService | PASS — trade handoff confirm producer |
| Explicit unlock resolution on level-up | PASS — unchanged reconcile path |
| Tests for sync merge + trade producer | PASS |

## Validation

```powershell
.\scripts\run-validation.ps1 -ChangedOnly
lune run tests/giant_level_cross_realm_sync_state.spec.luau
lune run tests/giant_level_state.spec.luau
lune run tests/giant_level_service_runtime_entrypoint.spec.luau
lune run tests/giant_level_trade_xp_producer_runtime_entrypoint.spec.luau
```

All pass locally.
