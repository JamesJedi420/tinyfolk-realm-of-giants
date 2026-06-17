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
| MemoryStore call failures | `memoryStoreCalls.throttledCount`, `memoryStoreCalls.partitionLimitCount`, `memoryStoreCalls.otherFailureCount`, `memoryStoreCalls.lastReason` | `MemoryStoreCallObservability.GetDiagnostics` (via adapter call sites) |

## Reason parity contract

- Aggregate `reasons.*` values must preserve source reasons whenever available.
- Missing dependency paths must return deterministic `*_api_unavailable` reasons.
- Aggregate result is accepted only when required dependencies for the requested snapshot are available.

## QA runbook (published-client safe)

### In-game aggregate snapshot

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
5. Validate MemoryStore call counters:
   - `memoryStoreCalls.throttledCount`, `partitionLimitCount`, and `otherFailureCount` are non-negative.
   - Under normal load these counters should remain near zero; spikes should correlate with server log lines prefixed `[MemoryStoreCallObservability]`.

### Published-client debug hooks (beyond query seam)

| Path | How to invoke | Response |
|---|---|---|
| Server query seam | In server command bar or ServerScript: `_G._MemoryStoreObservability_QueryAPI.GetSnapshot()` | Full aggregate snapshot table |
| Debug remote (published-safe) | Client fires `ReplicatedStorage.Remotes.MemoryStoreObservabilityDebugStateRequest` with `nil` payload; listen on `MemoryStoreObservabilityDebugStateResponse` | Same snapshot as query seam |
| Server logs | Watch Output → Server for `[MemoryStoreCallObservability]` lines after MemoryStore throttle/partition failures | Coalesced warn lines (30s per operation+reason); counters also in snapshot |

Debug remote notes:

- 2-second per-player cooldown; malformed payloads are rejected.
- Read-only: no gameplay or queue mutation.
- Prefer the query seam for Studio/server QA; use the remote when validating from a published client session.

### Roblox Memory Store Observability Dashboard QA

Roblox Creator Dashboard → place → **Memory Stores** (or **Observability → Memory Store** depending on UI revision).

| Dashboard signal | What it indicates | In-game parity check |
|---|---|---|
| Request volume / throughput | Aggregate MemoryStore traffic for the place | Not 1:1 with `memoryStoreCalls.*` (dashboard is place-wide; counters are per-server instance) |
| Throttle / rate-limit indicators | Platform-side throttling | Correlate spikes with `memoryStoreCalls.throttledCount` and `[MemoryStoreCallObservability] reason=memory_store_throttled` log lines during stress |
| Partition / capacity indicators | Structure nearing partition limits | Correlate with `memoryStoreCalls.partitionLimitCount` and `reason=memory_store_partition_limit` logs |
| Per-structure breakdown (when available) | Which named maps/queues are hot | Cross-check structure hints in server logs (`structure=tin_*`) against `MemoryStoreStructurePolicy` names |

Dashboard checklist:

1. Open dashboard while running a published or Studio playtest with admission/rescue/registry activity.
2. Confirm request charts move during queue enqueue/process and live-realm heartbeat windows.
3. Induce or observe a throttle window (burst enqueue/read) and confirm dashboard throttle metrics move in the same window as in-game `memoryStoreCalls.throttledCount`.
4. Record dashboard screenshots + matching `GetSnapshot().snapshot.memoryStoreCalls` excerpt for evidence when filing hardening issues.
5. Treat dashboard metrics as place-level telemetry; treat `GetSnapshot()` as per-server authoritative diagnostics for parity QA.

## Validation plan

```powershell
.\scripts\run-validation.ps1 -ChangedOnly
lune run tests/memory_store_call_observability.spec.luau
lune run tests/memory_store_observability_service.spec.luau
lune run tests/memory_store_adapter.spec.luau
lune run tests/transfer_lock_service_runtime_entrypoint.spec.luau
lune run tests/rescue_contract_admission_ingress_runtime_entrypoint.spec.luau
lune run tests/profile_teleport_handoff_admission_ingress_runtime_entrypoint.spec.luau
lune run tests/realm_admission_queue_service_runtime_entrypoint.spec.luau
lune run tests/live_realm_registry_service.spec.luau
```
