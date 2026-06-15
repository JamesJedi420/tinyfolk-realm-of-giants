# TIN-106 Realm Transfer Handoff Tokens Closure (2026-06-14)

## Issue

- ID: TIN-106
- Title: Implement realm transfer handoff tokens
- Linear: https://linear.app/spectranoir/issue/TIN-106/implement-realm-transfer-handoff-tokens

## Shipped

- `RealmTransferHandoffState` — deterministic realm session record and short-lived handoff token transitions keyed by `realmId`.
- `RealmTransferHandoffService` — server runtime with transfer-lock acquire on begin, session-record persistence, lock release on consume, and `_RealmTransferHandoffService_QueryAPI`.
- `MemoryStoreStructurePolicy.realmTransferSessions` — policy entry for future cross-server session replication.
- `ProfileTeleportHandoffService` — controlled-transfer begin/confirm now calls handoff token/session logic and `ApplyTransition` at ingress/arrival boundaries.
- Focused specs for shared state, handoff service runtime, and full handoff/orchestration pipeline.

## Acceptance criteria review

| Criterion | Result |
|---|---|
| Durable realm session records keyed by `realmId` | PASS |
| Short-lived handoff tokens with TTL | PASS |
| Transfer lock acquire on begin, consume on arrival | PASS |
| `ApplyTransition` at controlled-transfer begin/confirm | PASS |
| TeleportData remains non-authoritative | PASS |
| Existing handoff/admission/orchestration specs remain green | PASS |

## Validation

```powershell
.\scripts\run-validation.ps1 -ChangedOnly
lune run tests/realm_transfer_handoff_state.spec.luau
lune run tests/realm_transfer_handoff_service_runtime_entrypoint.spec.luau
lune run tests/profile_teleport_handoff_orchestration_runtime_entrypoint.spec.luau
lune run tests/profile_teleport_handoff_service_runtime_entrypoint.spec.luau
lune run tests/profile_teleport_destination_orchestration_runtime_entrypoint.spec.luau
lune run tests/profile_teleport_handoff_admission_ingress_runtime_entrypoint.spec.luau
lune run tests/memorystore_structure_policy.spec.luau
```

All commands passed locally.

## Out of scope (unchanged)

- Full teleport execution polish.
- Matchmaking expansion.
- MemoryStore-backed cross-server session replication (prototype uses in-memory records with `pendingRecovery` fallback on destination).

## Authority model

| Stage | Authoritative source |
|---|---|
| Source begin | Session record + transfer lock + `realmAssignment` in-flight transition |
| Transit | `pendingRecovery` on player profile |
| Destination confirm | Session record consume when present; otherwise `pendingRecovery` token match; then `realmAssignment` confirm |
