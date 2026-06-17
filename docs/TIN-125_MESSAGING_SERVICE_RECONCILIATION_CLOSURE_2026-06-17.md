# TIN-125 MessagingService Reconciliation — Closure

**Date:** 2026-06-17  
**Issue:** [TIN-125](https://linear.app/spectranoir/issue/TIN-125)  
**Milestone:** Admission and Queueing

## Shipped

- **Rescue contract board refresh:** `ReconcileRescueQueue` fans out hint-only `BroadcastNotify` via `_RescueContractHubSurface_QueryAPI` (`reason = rescue_queue_reconciled`).
- **Return recovery on join:** bootstrap enables `enableReturnRecoveryOnJoin`; `ReconcileReturnRecovery` checks spawn readiness and best-effort `OrchestrateDestinationArrival` when a player is resolvable.
- **Dropped-message harness:** `tests/notification_dropped_message_harness.spec.luau` simulates subscription-without-delivery and verifies authoritative reconcile + idempotent duplicate handling.
- **Prior partial delivery (TIN-59 Slice B):** realm-status reconcile already fans out `RaidBoardNotify`.

## Validation

```powershell
.\scripts\run-validation.ps1 -ChangedOnly
lune run tests/notification_reconciliation_service.spec.luau
lune run tests/notification_dropped_message_harness.spec.luau
.\scripts\run-tests.ps1
```

All commands passed locally on 2026-06-17.

## Deferred

- TIN-120 blind matchmaking queue.
- Cross-server party persistence.
- TIN-14 hub district growth.
- Full rescue contract board client UI (notify remote is hint-only; authoritative reads remain hub API).

## Linear comment (paste-ready)

TIN-125 full MessagingService reconciliation shipped.

**What shipped**
- Rescue queue reconcile → `RescueContractHubNotify` fanout after authoritative `GetPendingRescueQueueEntries`.
- Return recovery on player join via `enableReturnRecoveryOnJoin` + `ReconcileReturnRecovery` orchestration seam.
- Dropped-message integration harness spec for subscription-without-delivery recovery.
- Realm-status raid board fanout (from TIN-59 Slice B) retained.

**Validation**
- `.\scripts\run-validation.ps1 -ChangedOnly`
- `lune run tests/notification_reconciliation_service.spec.luau`
- `lune run tests/notification_dropped_message_harness.spec.luau`
- `.\scripts\run-tests.ps1` (CI green on PR)

**Evidence**
- Kickoff: `docs/TIN-125_MESSAGING_SERVICE_RECONCILIATION_KICKOFF_2026-06-17.md`
- PR: https://github.com/JamesJedi420/tinyfolk-realm-of-giants/pull/117

Ready for **Done**.
