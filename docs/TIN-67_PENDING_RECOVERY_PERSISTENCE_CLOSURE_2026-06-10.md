# TIN-67 Pending Recovery Persistence Closure (2026-06-10)

## Shipped

- Added `PendingRecoveryProfileState` with canonical normalize/apply helpers (`HasPersistedState`, `GetRecovery`, `CopyProfileField`, `ApplyPendingHandoff`, `ClearRecovery`).
- Extended `ProfilePersistenceGateway` clone/copy and load sanitization to round-trip `pendingRecovery` when present.
- Wired `ProfileTeleportHandoffService` to persist pending recovery before profile release, restore from loaded profile on spawn checks, and clear on ownership confirmation.
- Registered `pendingRecovery` namespace ownership in `EventStateOwnershipModel`.
- Added `tests/pending_recovery_profile_state.spec.luau` and gateway/runtime coverage.

## Validation

- `.\scripts\run-validation.ps1 -ChangedOnly` — pass
- `lune run tests/pending_recovery_profile_state.spec.luau` — pass
- `lune run tests/profile_persistence_gateway.spec.luau` — pass
- `lune run tests/profile_teleport_handoff_service_runtime_entrypoint.spec.luau` — pass
- `.\scripts\run-tests.ps1` — pass

## Remaining TIN-67 scope

- Skills, discovered realms, and party history persistence.
- Cross-server transfer and load-failure routing.

## Studio follow-up

Begin a cross-server handoff, disconnect before destination ownership confirms, rejoin, and confirm spawn remains blocked until ownership is ready and pending recovery clears from profile.
