# TIN-29 Realm Trade Conversion Rules — Kickoff

**Date:** 2026-06-15  
**Issue:** [TIN-29](https://linear.app/spectranoir/issue/TIN-29/implement-realm-trade-conversion-rules)  
**Related:** [TIN-241](https://linear.app/spectranoir/issue/TIN-241/giant-level-cross-realm-xp-sync-and-trade-xp-source)

## Slice boundary

- Minimal server-validated trade conversion on successful trade handoff confirm (`assignmentReason == "trade"`).
- `RealmTradeConversionConfig` — placeholder Wood/Stone/Essence deltas per trade role (source/destination).
- `RealmTradeConversionState` — pure validate/apply; idempotent by `trade-{role}-{baseOperationId}-{ownerUserId}` (same scheme as TIN-241 XP).
- `RealmTradeConversionProducer` + `RealmTradeConversionService` — session-only in-memory conversion ledger (not `giantRealmResourcePersistence`).
- Wired from `ProfileTeleportHandoffService` alongside `GiantLevelTradeXpProducer`.
- Debug seam: `_RealmTradeConversionService_QueryAPI` + realm-owner attributes for last conversion snapshot.

## Constraints

- No persistence to realm save; session/debug ledger only (TIN-64 resource ledger unchanged).
- No full cross-server trade execution or matchmaking expansion.
- No final economy balancing.
- Conversion applies locally when active realm owner matches source or destination; remote realm symmetric awards deferred.

## Deferred

- Cross-server symmetric source-side conversion delivery.
- Persisted trade conversion integration with `giantRealmResourcePersistence`.
- Trade UX / F-key flows.

## Validation

```powershell
.\scripts\run-validation.ps1 -ChangedOnly
lune run tests/realm_trade_conversion_state.spec.luau
lune run tests/realm_trade_conversion_producer_runtime_entrypoint.spec.luau
lune run tests/profile_teleport_handoff_service_runtime_entrypoint.spec.luau
.\scripts\run-tests.ps1
```
