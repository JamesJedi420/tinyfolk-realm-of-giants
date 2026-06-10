# TIN-66 Reputation Ladder + Escape-Failure Trophies — Kickoff

**Date:** 2026-06-09  
**Issue:** [TIN-66](https://linear.app/spectranoir/issue/TIN-66/implement-giant-trophy-and-reputation-system)

## Slice boundary

- `GiantReputationConfig` — score awards by trophy kind, rank threshold table, rank titles.
- `GiantReputationState` — pure `ApplyScoreEvent`, `ResolveRankFromScore`, idempotent by `operationId`.
- `GiantReputationService` — `_GiantReputationService_QueryAPI`, realm-owner attribute projection.
- Giant realm save root `giantReputationPersistence: { score, rank, recentEvents[] }`.
- Wire reputation score grants from `TrophyService` on accepted trophy events (shared `operationId`).
- Escape-failure trophy integration tests for `escaped` containment ends (`containment_escape_failure` kind).
- Realm-owner debug attributes: `GiantReputationScore`, `GiantReputationRank`, `GiantReputationRankTitle`, `GiantReputationScoreToNextRank`.

## Deferred

- Trophy case / world display props.
- Tinyfolk opt-out UI and name display policy.
- Raid-defense and negotiated-release trophy kinds.
- Cross-realm reputation sync.

## Validation

```powershell
lune run tests/giant_reputation_state.spec.luau
lune run tests/giant_reputation_service_runtime_entrypoint.spec.luau
lune run tests/trophy_state.spec.luau
lune run tests/trophy_service_runtime_entrypoint.spec.luau
lune run tests/containment_reward_resolver.spec.luau
lune run tests/giant_realm_save_schema.spec.luau
.\scripts\run-validation.ps1 -ChangedOnly
```
