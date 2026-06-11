# TIN-67 Party History Persistence Closure (2026-06-11)

## Shipped

- Added `PartyHistoryProfileState` with canonical normalize/append/copy helpers (`HasPersistedState`, `GetHistory`, `CopyProfileField`, `AppendEntry`).
- Extended `ProfilePersistenceGateway` clone/copy and load sanitization to round-trip `partyHistory` when present.
- Wired `RealmAdmissionQueueService.EnqueueAdmission` to persist bounded party history for each admission party member on successful enqueue.
- Registered `partyHistory` namespace ownership in `EventStateOwnershipModel`.
- Added `tests/party_history_profile_state.spec.luau` and gateway/runtime coverage.

## Validation

- `.\scripts\run-validation.ps1 -ChangedOnly` — pass
- `lune run tests/party_history_profile_state.spec.luau` — pass
- `lune run tests/profile_persistence_gateway.spec.luau` — pass
- `lune run tests/realm_admission_queue_service_runtime_entrypoint.spec.luau` — pass
- `.\scripts\run-tests.ps1` — pass

## Remaining TIN-67 scope

- Cross-server transfer orchestration.
- Load-failure safe routing (`ProfilePersistenceLifecycle`).
- Runtime skill unlock producer (once catalog has progression skills).

## Studio follow-up

Accept a rescue contract or party admission with multiple members, leave, rejoin, and confirm `partyHistory` round-trips through profile load/save for each member.
