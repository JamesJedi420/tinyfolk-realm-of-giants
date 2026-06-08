# TIN-64 Giant Realm Resource Economy Slice C Kickoff (2026-06-08)

## Issue
- ID: TIN-64
- Title: Implement Giant realm resource economy
- Linear: https://linear.app/spectranoir/issue/TIN-64/implement-giant-realm-resource-economy

## Slice C boundary
- **Defended raid producer:** award persistent ledger resources when a Giant successfully applies remote route pressure (`RemoteControlStationService.requestRoutePressure`).
- **Treasury HUD:** server attribute projection of ledger + session pools; Giant-only client HUD following raid/score feedback patterns.
- **Cross-server pair history:** MemoryStore-backed pair anti-farming for `GiantRealmResourceResolver` (with in-memory fallback).

## Key files
- `src/ReplicatedStorage/Shared/GiantRealm/GiantRealmResourceState.luau` — `DefendedRaidRoutePressure` source kind
- `src/ReplicatedStorage/Shared/GiantRealm/GiantRealmResourcePairHistoryState.luau`
- `src/ReplicatedStorage/Shared/GiantRealm/GiantRealmTreasuryPresentation.luau`
- `src/ReplicatedStorage/Shared/Config/GiantRealmTreasuryConfig.luau`
- `src/ServerScriptService/Services/RealmResourcePairHistoryStore.luau`
- `src/ServerScriptService/Services/RealmResourcePairHistoryService.server.luau`
- `src/ServerScriptService/Services/GiantRealmResourceResolver.luau`
- `src/ServerScriptService/Services/GiantBuildModeService.server.luau` — treasury projection
- `src/ServerScriptService/Services/RemoteControlStationService.server.luau` — defended raid hook
- `src/ServerScriptService/Services/MemoryStoreStructurePolicy.luau` — `realmResourcePairHistory`
- `src/StarterPlayer/StarterPlayerScripts/Client/GiantTreasuryHudClient.client.luau`

## Design notes
- Defended raid awards: fixed 3 Essence / 2 Wood / 1 Stone; idempotent via `realm-resource:defended-raid:{stationId}:{routeId}:{warningStartedAt}`.
- No counterparty on defended raids → no pair depreciation (pair history applies to counterparty-bearing sources).
- Pair history key: `{ownerUserId}.{counterpartyUserId}.{sourceKind}` (MemoryStore-safe segments); TTL 300s in MemoryStore.
- Treasury HUD: ledger from `GetResourceLedgerSnapshot()`; session wood/stone from `ResourceFlowState`; essence session pool deferred.

## Validation
```powershell
lune run tests/giant_realm_resource_state.spec.luau
lune run tests/giant_realm_resource_resolver.spec.luau
lune run tests/giant_realm_resource_pair_history_state.spec.luau
lune run tests/realm_resource_pair_history_store.spec.luau
lune run tests/giant_realm_treasury_presentation.spec.luau
lune run tests/memorystore_structure_policy.spec.luau
lune run tests/remote_control_station_service_runtime_entrypoint.spec.luau
lune run tests/giant_build_mode_service_runtime_entrypoint.spec.luau
.\scripts\run-validation.ps1 -ChangedOnly
.\scripts\run-tests.ps1
```
