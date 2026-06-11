# TIN-67 Pending Recovery Persistence Kickoff (2026-06-10)

## Issue

- ID: TIN-67 (focused slice: pending recovery hardening)
- Title: Implement Tinyfolk persistent profile
- Linear: https://linear.app/spectranoir/issue/TIN-67/implement-tinyfolk-persistent-profile

## Scope

- Add `PendingRecoveryProfileState` for canonical teleport handoff recovery normalize/apply/copy helpers.
- Extend `ProfilePersistenceGateway` clone/copy and load sanitization for `pendingRecovery`.
- Wire `ProfileTeleportHandoffService` begin/confirm/spawn paths through the shared profile-state module.
- Register `pendingRecovery` namespace ownership in `EventStateOwnershipModel`.
- Add `tests/pending_recovery_profile_state.spec.luau` and gateway/runtime coverage.

## Boundary

- Bounded `pendingRecovery` snapshot only (`handoffToken`, `targetRealmId`, `startedAt`, `status`).
- Persist before profile release on successful handoff enqueue; restore in-memory pending state from loaded profile on destination join checks.
- No cross-server transfer orchestration or load-failure routing.

## Validation

```powershell
.\scripts\run-validation.ps1 -ChangedOnly
lune run tests/pending_recovery_profile_state.spec.luau
lune run tests/profile_persistence_gateway.spec.luau
lune run tests/profile_teleport_handoff_service_runtime_entrypoint.spec.luau
.\scripts\run-tests.ps1
```

## Deferred

- Skills, discovered realms, and party history persistence.
- Cross-server transfer and load-failure routing.
