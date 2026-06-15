# TIN-29 Cross-Server Trade Conversion Delivery — Kickoff

**Date:** 2026-06-15  
**Issue:** [TIN-29](https://linear.app/spectranoir/issue/TIN-29) deferred follow-up  
**Related:** [TIN-241](https://linear.app/spectranoir/issue/TIN-241), [TIN-64](https://linear.app/spectranoir/issue/TIN-64)

## Slice boundary

- Cross-server symmetric source/destination trade conversion delivery via `realmTradeConversionPending` MemoryStore buffer (mirrors TIN-241 XP pending pattern).
- `RealmTradeConversionCrossRealmSyncState` — pure encode/decode, merge/replay onto session conversion ledger.
- `RealmTradeConversionPendingStore` + `MemoryStoreStructurePolicy.realmTradeConversionPending`.
- `RealmTradeConversionService` — publish on remote trade confirm, merge on active owner load, ack when session ledger contains operation ids.

## Constraints

- Session-only conversion ledger unchanged (no `giantRealmResourcePersistence` bridge in this slice).
- Shared `trade-{role}-{baseOperationId}-{ownerUserId}` idempotency with TIN-241 XP.
- No full cross-server trade execution UX or economy balancing.

## Deferred

- Persisted trade conversion integration with `giantRealmResourcePersistence`.
- Trade F-key / matchmaking expansion.

## Validation

```powershell
.\scripts\run-validation.ps1 -ChangedOnly
lune run tests/realm_trade_conversion_cross_realm_sync_state.spec.luau
lune run tests/realm_trade_conversion_*.spec.luau
lune run tests/giant_level_*.spec.luau
.\scripts\run-tests.ps1
```
