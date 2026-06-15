# TIN-11 Realm Transfer State Model Kickoff (2026-06-14)

## Issue

- ID: TIN-11
- Title: Implement realm transfer state model
- Linear: https://linear.app/spectranoir/issue/TIN-11/implement-realm-transfer-state-model
- Depends on: TIN-49 location categories and transfer reason shell

## Scope

- Server-owned `realmAssignment` player-profile namespace with validated snapshots.
- Deterministic `RealmTransferState` transition resolver for capture, rescue, escape return, trade, and party admission flows.
- `RealmTransferAssignmentService` runtime seam with profile persistence, hydration, diagnostics, and `_RealmTransferAssignmentService_QueryAPI`.
- Gateway sanitization and `EventStateOwnershipModel` namespace ownership for `realmAssignment`.

## Boundary

- No handoff token implementation (TIN-106).
- No durable realm session records (TIN-106).
- No full matchmaking or save-pipeline redesign.
- No mandatory wiring into `ProfileTeleportHandoffService` in this slice.

## Inspect first

- `docs/TIN-49_PERSISTENT_REALM_ARCHITECTURE.md`
- `PendingRecoveryProfileState`, `EventStateOwnershipModel`, `ProfileTeleportHandoffService`
- `ProfilePersistenceGateway` profile field sanitization paths

## Validation

```powershell
.\scripts\run-validation.ps1 -ChangedOnly
lune run tests/realm_assignment_profile_state.spec.luau
lune run tests/realm_transfer_state.spec.luau
lune run tests/realm_transfer_assignment_service_runtime_entrypoint.spec.luau
```

## Deferred

- TIN-106 handoff tokens and durable realm session records keyed by `realmId`.
- Teleport execution polish and producer ingress wiring to assignment transitions.
