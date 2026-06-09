# TIN-66 Giant Trophy Foundation — Kickoff

**Date:** 2026-06-08  
**Issue:** [TIN-66](https://linear.app/spectranoir/issue/TIN-66/implement-giant-trophy-and-reputation-system)

## Slice boundary (foundation)

- Server-owned trophy ledger on giant-realm save root (`trophyPersistence.trophies`).
- Display-safe metadata only (anonymized `targetDisplayToken`, no raw Tinyfolk names).
- Record trophies from capture success and terminal containment custody ends.
- Project realm-owner debug attributes (`GiantTrophyCount`, `GiantTrophyLatestSummary`, `GiantTrophyLatestKind`).

## Deferred

- Trophy case / world display props.
- Giant reputation score ladder (separate from trophy ledger).
- Tinyfolk opt-out UI and name display policy.
- Raid-defense and negotiated-release trophy kinds beyond containment end mapping.

## Validation

```powershell
lune run tests/trophy_state.spec.luau
lune run tests/trophy_service_runtime_entrypoint.spec.luau
lune run tests/containment_reward_resolver.spec.luau
lune run tests/giant_realm_save_schema.spec.luau
.\scripts\run-validation.ps1 -ChangedOnly
```
