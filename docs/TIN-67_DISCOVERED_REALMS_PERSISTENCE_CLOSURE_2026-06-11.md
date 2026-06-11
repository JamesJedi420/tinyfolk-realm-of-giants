# TIN-67 Discovered Realms Persistence Closure (2026-06-11)

## Shipped

- Added `DiscoveredRealmsProfileState` with canonical normalize/record/copy helpers (`HasPersistedState`, `GetDiscoveries`, `IsDiscovered`, `CopyProfileField`, `RecordDiscovery`).
- Extended `ProfilePersistenceGateway` clone/copy and load sanitization to round-trip `discoveredRealms` when present.
- Wired `ProfileTeleportHandoffService` destination ownership confirm paths to persist first realm discovery before clearing pending handoff.
- Registered `discoveredRealms` namespace ownership in `EventStateOwnershipModel`.
- Added `tests/discovered_realms_profile_state.spec.luau` and gateway/runtime coverage.

## Validation

- `.\scripts\run-validation.ps1 -ChangedOnly` — pass
- `lune run tests/discovered_realms_profile_state.spec.luau` — pass
- `lune run tests/profile_persistence_gateway.spec.luau` — pass
- `lune run tests/profile_teleport_handoff_service_runtime_entrypoint.spec.luau` — pass
- `.\scripts\run-tests.ps1` — pass

## Remaining TIN-67 scope

- Skills and party history persistence.
- Cross-server transfer and load-failure routing.

## Studio follow-up

Complete a realm admission handoff, confirm destination ownership, leave, rejoin, and confirm `discoveredRealms` round-trips through profile load/save.
