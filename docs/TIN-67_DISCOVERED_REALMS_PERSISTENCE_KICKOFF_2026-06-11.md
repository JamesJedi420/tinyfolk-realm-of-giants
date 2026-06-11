# TIN-67 Discovered Realms Persistence Kickoff (2026-06-11)

## Issue

- ID: TIN-67 (focused slice: discovered realms hardening)
- Title: Implement Tinyfolk persistent profile
- Linear: https://linear.app/spectranoir/issue/TIN-67/implement-tinyfolk-persistent-profile

## Scope

- Add `DiscoveredRealmsProfileState` for canonical realm discovery normalize/record/copy helpers.
- Extend `ProfilePersistenceGateway` clone/copy and load sanitization for `discoveredRealms`.
- Wire `ProfileTeleportHandoffService` destination ownership confirm paths to record first realm discovery.
- Register `discoveredRealms` namespace ownership in `EventStateOwnershipModel`.
- Add `tests/discovered_realms_profile_state.spec.luau` and gateway/runtime coverage.

## Boundary

- Bounded `discoveredRealms` set only (`realmId`, `firstDiscoveredAt`; idempotent by realmId; default limit 50).
- Write on first successful destination ownership confirmation after realm admission handoff.
- Distinct from `escapeHistory` (escape outcomes with loot/reward metadata, not first-visit discovery).
- No cross-server transfer orchestration or load-failure routing.

## Validation

```powershell
.\scripts\run-validation.ps1 -ChangedOnly
lune run tests/discovered_realms_profile_state.spec.luau
lune run tests/profile_persistence_gateway.spec.luau
lune run tests/profile_teleport_handoff_service_runtime_entrypoint.spec.luau
.\scripts\run-tests.ps1
```

## Deferred

- Skills and party history persistence.
- Cross-server transfer and load-failure routing.

## Studio follow-up

Complete a realm admission handoff, confirm destination ownership, leave, rejoin, and confirm `discoveredRealms` round-trips through profile load/save.
