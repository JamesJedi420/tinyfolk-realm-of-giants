# TIN-11 Realm Transfer State Model Closure (2026-06-14)

## Issue

- ID: TIN-11
- Title: Implement realm transfer state model
- Linear: https://linear.app/spectranoir/issue/TIN-11/implement-realm-transfer-state-model

## Shipped

- `RealmAssignmentProfileState` — canonical `realmAssignment` profile namespace (`locationCategory`, `realmId`, `realmOwnerUserId`, `assignmentReason`, `updatedAt`) with sanitize/copy/apply helpers.
- `RealmTransferState` — deterministic transition resolver for capture, rescue, escape return, trade, party admission, arrival confirm, hub return, and abort-to-hub; legacy `pendingRecovery` category derivation retained.
- `RealmTransferAssignmentService` — server runtime with profile hydrate/persist, transition application, diagnostics, and `_RealmTransferAssignmentService_QueryAPI`.
- `ProfilePersistenceGateway` and `EventStateOwnershipModel` updated for `realmAssignment` ownership and load sanitization.
- Focused specs for profile state, transfer state machine, and runtime entrypoint.

## Acceptance criteria review

| Criterion | Result |
|---|---|
| Explicit `realmAssignment` read model on player profile | PASS |
| Validated transitions for capture / escape / trade ingress | PASS |
| Server-owned debug/query surfaces for downstream handoff | PASS |
| No handoff token or session-record scope leak | PASS |

## Validation

```powershell
.\scripts\run-validation.ps1 -ChangedOnly
lune run tests/realm_assignment_profile_state.spec.luau
lune run tests/realm_transfer_state.spec.luau
lune run tests/realm_transfer_assignment_service_runtime_entrypoint.spec.luau
lune run tests/event_state_ownership_model.spec.luau
```

All commands passed locally.

## Out of scope (unchanged)

- Handoff tokens and durable realm session records (TIN-106).
- Full teleport/handoff producer wiring.
- Matchmaking or save-pipeline redesign.

## Downstream handoff

TIN-106 should consume `_RealmTransferAssignmentService_QueryAPI.ApplyTransition` at controlled-transfer begin/confirm boundaries and keep TeleportData non-authoritative per TIN-49.
