# TIN-121 Rescue Contract Queue — Kickoff

**Date:** 2026-06-17  
**Issue:** [TIN-121](https://linear.app/spectranoir/issue/TIN-121/implement-rescue-contract-queue)  
**Milestone:** Admission and Queueing  
**Related:** [TIN-72](https://linear.app/spectranoir/issue/TIN-72) (rescue contract route/realm), [TIN-125](https://linear.app/spectranoir/issue/TIN-125) (messaging reconciliation fanout)

## Goal

Surface live custody rescue opportunities through an ephemeral cross-server queue that hub servers can list and accept safely.

## In scope

### Shared

- `RescueContractQueueState` store validation (`ValidateEntry`, `NewEntry`, `IsExpired`) and optional `storeReceiptId`.
- `RescueContractHubState` / `RescueContractHubPresentation` for hub board projection copy.
- `RescueContractConfig` hub remotes, board anchor prefix, list limits, and reconcile batch size.

### Server

- `RescueContractQueueStore` — MemoryStore producer/consumer for `rescueContractQueue` policy.
- `RescueContractQueueService` — enqueue, reconcile-from-store ingest, explicit receipt removal (`_RescueContractQueue_QueryAPI`).
- `RescueContractService` — publish enqueue, ingest seam, accept/expiry store receipt cleanup.
- `RescueContractHubService` — list/accept remotes backed by `_RescueContractHubSurface_QueryAPI`.
- `NotificationReconciliationService.ReconcileRescueQueue` — reconcile MemoryStore before authoritative local read.
- `TinyfolkHubState` — `rescue_contract_board` activity eligibility.

### Client / map

- `RescueContractClient` — board UI wired to list/accept/notify remotes.
- `InteractionResolver` — F-key opens board via `RescueContractBoardOpenRequested` at `RescueContractBoardHub_*`.
- `TinyfolkWorld` anchor `RescueContractBoardHub_A`.

## Out of scope / deferred

- Rich matchmaking UX polish (skillBand/toolTier tuning).
- Cross-server party persistence.
- RescueContractHubNotify discoverability alternate path beyond refresh-on-notify.

## Validation

```powershell
.\scripts\run-validation.ps1 -ChangedOnly
lune run tests/rescue_contract_queue_state.spec.luau
lune run tests/rescue_contract_hub_state.spec.luau
lune run tests/rescue_contract_hub_presentation.spec.luau
lune run tests/rescue_contract_queue_service_runtime_entrypoint.spec.luau
lune run tests/rescue_contract_hub_service_runtime_entrypoint.spec.luau
lune run tests/rescue_contract_service_runtime_entrypoint.spec.luau
```

## Acceptance mapping

| Criterion | Implementation |
|---|---|
| Captured Tinyfolk generates queue item | `RescueContractService.requestRescueContract` → `publishRescueQueueEntry` |
| Queue item fields (capturedUserId, realmId, sessionId, rewardHint, dangerRating, expiration) | `RescueContractQueueState.QueueEntry` + publish path |
| Hub reads and surfaces eligible contracts | `RescueContractHubService` list remote + `RescueContractHubState.ProjectContracts` |
| Accept creates handoff lock and marks/removes queue item | `acceptRescueQueueEntry` + store receipt removal |
| Expired contracts resolve safely | `PruneExpired` + store receipt removal + optional handoff expiry hook |
