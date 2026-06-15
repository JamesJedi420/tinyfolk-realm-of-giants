# TIN-106 Cross-Server Session Replication Closure (2026-06-15)

## Issue

- ID: TIN-106 (remainder)
- Title: Implement realm transfer handoff tokens
- Linear: https://linear.app/spectranoir/issue/TIN-106/implement-realm-transfer-handoff-tokens

## Shipped

- `RealmTransferSessionStore` — MemoryStore-backed session record persistence via `realmTransferSessions` policy with in-memory fallback for tests/offline.
- `RealmTransferHandoffState` — session record encode/decode, validation, and `InvalidateHandoff` lifecycle transition.
- `RealmTransferHandoffService` — replaced prototype in-memory map with store; added `InvalidateHandoffOnAbort` and `ResolveExpiredSession`.
- `ProfileTeleportHandoffService` — abort/logout session invalidation, expired-session `pendingRecovery` authority resolution, `ConfirmHubReturn` for escape-return confirms, invalid-token safe-fallback routing.

## Acceptance criteria review

| Criterion | Result |
|---|---|
| MemoryStore-backed cross-server session replication | PASS |
| Session updates on escape/logout/return/failed-arrival paths | PASS |
| Expired-session safe resolution | PASS |
| Invalid-token safe-fallback routing | PASS |
| `pendingRecovery` remains transit authority | PASS |
| TeleportData remains non-authoritative | PASS |
| Focused handoff/orchestration specs green | PASS |

## Validation

```powershell
.\scripts\run-validation.ps1 -ChangedOnly
lune run tests/realm_transfer_handoff_state.spec.luau
lune run tests/realm_transfer_session_store.spec.luau
lune run tests/realm_transfer_handoff_service_runtime_entrypoint.spec.luau
lune run tests/profile_teleport_handoff_service_runtime_entrypoint.spec.luau
lune run tests/profile_teleport_handoff_orchestration_runtime_entrypoint.spec.luau
lune run tests/profile_teleport_handoff_admission_ingress_runtime_entrypoint.spec.luau
lune run tests/profile_teleport_destination_orchestration_runtime_entrypoint.spec.luau
```

All commands passed locally.

## Authority model (unchanged)

| Stage | Authoritative source |
|---|---|
| Source begin | Session record + transfer lock + `realmAssignment` in-flight transition |
| Transit | `pendingRecovery` on player profile |
| Destination confirm | Session record consume when present; expired/missing falls back to `pendingRecovery` token match; invalid token routes safe-fallback |

## Out of scope (unchanged)

- Full teleport execution polish.
- Matchmaking expansion.
