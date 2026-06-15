# TIN-241 Giant Level Cross-Realm XP Sync — Kickoff

**Date:** 2026-06-15  
**Issue:** [TIN-241](https://linear.app/spectranoir/issue/TIN-241/giant-level-cross-realm-xp-sync-and-trade-xp-source)

## Slice boundary

- Cross-realm XP sync via `giantLevelPendingXp` MemoryStore buffer keyed by `realmId`, merged on realm load, acked on save snapshot.
- `GiantLevelCrossRealmSyncState` pure merge/replay/encode rules; `GiantLevelPendingXpStore` adapter seam.
- `GiantLevelService` publishes pending XP on grant, merges pending on `ApplyPersistenceState`, prunes on `BuildPersistenceState`.
- Trade XP source: `TradeSuccess` event kind (+30), `GiantLevelTradeXpProducer`, wired from `ProfileTeleportHandoffService` trade handoff confirm.
- Idempotent `operationId` keys for trade: `trade-{role}-{baseOperationId}-{ownerUserId}`.

## Constraints

- No save-pipeline redesign; `giantLevelPersistence` remains on realm profile per TIN-49.
- Server-authoritative XP writes only.
- Explicit unlock resolution preserved (no modifier inflation from raw level).

## Deferred

- Full TIN-29 trade conversion runtime and cross-server trade execution polish.
- Matchmaking expansion.

## Validation

```powershell
.\scripts\run-validation.ps1 -ChangedOnly
lune run tests/giant_level_*.spec.luau
```
