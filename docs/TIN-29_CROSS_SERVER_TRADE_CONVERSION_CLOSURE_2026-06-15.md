# TIN-29 Cross-Server Trade Conversion Delivery — Closure

**Date:** 2026-06-15  
**Issue:** [TIN-29](https://linear.app/spectranoir/issue/TIN-29) deferred follow-up

## Shipped

- `RealmTradeConversionCrossRealmSyncState` — pending buffer encode/decode, idempotent merge/replay onto session conversion ledger.
- `RealmTradeConversionPendingStore` + `MemoryStoreStructurePolicy.realmTradeConversionPending` — cross-server pending conversion buffer keyed by `realmId`.
- `RealmTradeConversionService` — publish on remote trade confirm, merge on active owner access, ack when session ledger contains operation ids; `MergePendingConversions` query seam.
- Shared `trade-{role}-{baseOperationId}-{ownerUserId}` idempotency with TIN-241 XP.

## Acceptance criteria

| Criterion | Result |
|---|---|
| Source-side cross-server conversion delivery mirrors TIN-241 XP pending pattern | PASS |
| Destination-side remote publish when trade confirmed off-realm | PASS |
| Session ledger merge + ack without duplicate awards | PASS |
| No persistence bridge to `giantRealmResourcePersistence` | PASS — deferred per slice boundary |

## Validation

```powershell
.\scripts\run-validation.ps1 -ChangedOnly
lune run tests/realm_trade_conversion_cross_realm_sync_state.spec.luau
lune run tests/realm_trade_conversion_*.spec.luau
lune run tests/giant_level_cross_realm_sync_state.spec.luau
.\scripts\run-tests.ps1
```

All pass locally.
