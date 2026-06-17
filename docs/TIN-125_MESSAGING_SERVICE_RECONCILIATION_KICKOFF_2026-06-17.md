# TIN-125 MessagingService Reconciliation — Kickoff

**Date:** 2026-06-17  
**Issue:** [TIN-125](https://linear.app/spectranoir/issue/TIN-125)  
**Milestone:** Admission and Queueing  
**Related:** [TIN-59](https://linear.app/spectranoir/issue/TIN-59) (raid board notify fanout, partial), [TIN-128](https://linear.app/spectranoir/issue/TIN-128) (announcement channel)

## Goal

Complete full MessagingService reconciliation so no critical state depends on message delivery. Fanout hints refresh hub boards; authoritative reads recover dropped or duplicate messages.

## Prerequisites

| Dependency | Status | Notes |
|---|---|---|
| Notification schema / adapter / subscriptions | **Done** | `NotificationMessageSchema`, `MessagingServiceAdapter`, `NotificationSubscriptionManager` |
| Reconciliation channels (admission, rescue, realm, announcement) | **Done** | `NotificationReconciliationService` |
| Realm-status raid board notify (TIN-59 Slice B) | **Done** | `ReconcileRealmStatus` → `BroadcastNotify` |
| Rescue contract hub surface | **Done** | `_RescueContractHubSurface_QueryAPI` |
| Profile teleport handoff orchestration | **Done** | `ProfileTeleportHandoffService` |

## Slice boundary (in scope)

### Rescue contract board refresh

- `RescueContractConfig.Remotes.Notify` + `BroadcastNotify` on `_RescueContractHubSurface_QueryAPI`.
- `NotificationReconciliationService.ReconcileRescueQueue` fans out `{ reason = "rescue_queue_reconciled", at }` after successful reconcile.

### Return recovery on join

- `NotificationReconciliationService.ReconcileReturnRecovery` calls `CanSpawnGameplayForUserId` and best-effort `OrchestrateDestinationArrival` when a player is resolvable.
- Bootstrap enables `enableReturnRecoveryOnJoin` to reconcile each `PlayerAdded` (and existing players at start).

### Dropped-message test harness

- `tests/notification_dropped_message_harness.spec.luau` — subscription present but no callback delivery; reconciliation + notify fanout recover authoritative state; duplicate handling remains idempotent.

## Out of scope / deferred

- TIN-120 blind matchmaking queue.
- Cross-server party persistence.
- TIN-14 hub district growth.
- Full rescue contract board client UI (hint remote only; authoritative read via hub API).

## Validation

```powershell
.\scripts\run-validation.ps1 -ChangedOnly
lune run tests/notification_reconciliation_service.spec.luau
lune run tests/notification_dropped_message_harness.spec.luau
.\scripts\run-tests.ps1
```
