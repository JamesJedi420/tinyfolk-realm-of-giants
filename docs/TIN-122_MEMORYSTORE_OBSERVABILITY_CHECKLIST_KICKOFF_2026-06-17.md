# TIN-122 MemoryStore Observability Hardening - Kickoff

**Date:** 2026-06-17  
**Issue:** [TIN-122](https://linear.app/spectranoir/issue/TIN-122)  
**Milestone:** Admission and Queueing  
**Related:** [TIN-120](https://linear.app/spectranoir/issue/TIN-120), [TIN-121](https://linear.app/spectranoir/issue/TIN-121), [TIN-125](https://linear.app/spectranoir/issue/TIN-125)

## Goal

Add one canonical, read-only MemoryStore observability surface for QA and hardening checks across admission, rescue, live realm registry, and transfer lock coordination.

## In scope

- Canonical checklist and metric naming for cross-server observability.
- One aggregate query seam that collects diagnostics from existing service query APIs.
- Minimal diagnostics gap fill for transfer-lock failures.
- Focused parity tests for aggregate output and dependency-failure reason reporting.

## Out of scope

- Gameplay behavior or queue semantics changes.
- Durable persistence changes.
- New producer/dispatcher pathways.

## Canonical observability checklist

| Metric group | Canonical fields | Source seam |
|---|---|---|
| Queue depth | `queueDepth.rescuePendingCount`, `queueDepth.admissionLastProcessedCount` | `_RescueContractHubSurface_QueryAPI.GetPendingRescueQueueEntries`, `_RealmAdmissionQueue_QueryAPI.GetProcessingDiagnostics` |
| Active realms | `realm.activeRealmCount` | `_LiveRealmRegistryHubSurface_QueryAPI.ListLiveRealmAvailability` |
| Stale registry indicators | `realm.staleRegistryIndicators` (`refreshFailed`, `pruneFailed`, `lastReason`) | `_LiveRealmRegistry_QueryAPI.GetDiagnostics` |
| Transfer lock failures | `transferLock.failedAcquireCount`, `transferLock.lastReason` | `_TransferLock_QueryAPI.GetDiagnostics` |
| Retry/fallback counters | `ingress.rescue`, `ingress.profileTeleport`, `admission.retryDeferred` | `_RescueContractService_QueryAPI.GetAdmissionIngressDiagnostics`, `_ProfileTeleportHandoffService_QueryAPI.GetAdmissionIngressDiagnostics`, `_RealmAdmissionQueue_QueryAPI.GetProcessingDiagnostics` |

## Reason parity contract

- Aggregate `reasons.*` values must preserve source reasons whenever available.
- Missing dependency paths must return deterministic `*_api_unavailable` reasons.
- Aggregate result is accepted only when required dependencies for the requested snapshot are available.

## QA runbook (published-client safe)

1. Call aggregate observability query seam.
2. Verify field shape is stable and fully populated for currently active services.
3. Validate parity:
   - rescue ingress `lastReason` equals aggregate rescue ingress reason.
   - profile teleport ingress `lastReason` equals aggregate profile teleport reason.
   - transfer lock `lastReason` equals aggregate transfer lock reason.
4. Validate queue + realm health expectations:
   - `queueDepth.rescuePendingCount >= 0`
   - `realm.activeRealmCount >= 0`
   - `transferLock.failedAcquireCount` does not spike unexpectedly under normal retries.

## Validation plan

```powershell
.\scripts\run-validation.ps1 -ChangedOnly
lune run tests/memory_store_observability_service.spec.luau
lune run tests/transfer_lock_service_runtime_entrypoint.spec.luau
lune run tests/rescue_contract_admission_ingress_runtime_entrypoint.spec.luau
lune run tests/profile_teleport_handoff_admission_ingress_runtime_entrypoint.spec.luau
lune run tests/realm_admission_queue_service_runtime_entrypoint.spec.luau
lune run tests/live_realm_registry_service.spec.luau
```
