# TIN-122 MemoryStore Observability Hardening — Closure

**Date:** 2026-06-17  
**Issue:** [TIN-122](https://linear.app/spectranoir/issue/TIN-122)  
**Milestone:** Admission and Queueing

## Shipped

### Batch 1 (PR #121)

- Canonical observability checklist and metric naming in kickoff doc.
- `MemoryStoreObservabilityService` aggregate read-only `GetSnapshot` seam across admission, rescue, registry, transfer lock, and ingress diagnostics.
- Transfer lock diagnostics gap fill (`failedAcquireCount`, `lastReason`, `activeLockCount`).
- Focused parity tests in `tests/memory_store_observability_service.spec.luau`.

### Batch 2 (this slice)

- **`MemoryStoreCallObservability`:** classifies MemoryStore throttle/partition-limit failures, increments per-server counters, and emits coalesced server warn logs (30s per operation+reason) from `MemoryStoreAdapter` call sites.
- **Aggregate snapshot extension:** `snapshot.memoryStoreCalls` exposes throttled/partition/other failure counters plus `lastReason` / `lastOperation`.
- **Published-client debug remote:** `MemoryStoreObservabilityDebugStateRequest` / `MemoryStoreObservabilityDebugStateResponse` returns the same snapshot as `_MemoryStoreObservability_QueryAPI.GetSnapshot()` (2s per-player cooldown).
- **Kickoff doc:** dashboard QA checklist, dashboard vs in-game parity notes, and documented debug invocation paths beyond the query seam.

## Validation

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
.\scripts\run-tests.ps1
```

## Out of scope (unchanged)

- Queue semantics or gameplay behavior changes.
- Durable persistence changes.
- New producer/dispatcher pathways.

## Linear comment (paste-ready)

TIN-122 MemoryStore observability checklist complete.

**What shipped**
- Batch 1: aggregate `GetSnapshot` seam + transfer-lock diagnostics (PR #121).
- Batch 2: MemoryStore throttle/partition-limit logging via adapter wrapper, `memoryStoreCalls` snapshot fields, published-client debug remote, dashboard QA checklist in kickoff doc.

**Validation**
- `.\scripts\run-validation.ps1 -ChangedOnly`
- `lune run tests/memory_store_call_observability.spec.luau`
- `lune run tests/memory_store_observability_service.spec.luau`
- `lune run tests/memory_store_adapter.spec.luau`
- Focused admission/rescue/registry/transfer-lock runtime specs + full `.\scripts\run-tests.ps1` (CI green on PR)

**Evidence**
- Kickoff: `docs/TIN-122_MEMORYSTORE_OBSERVABILITY_CHECKLIST_KICKOFF_2026-06-17.md`
- Closure: `docs/TIN-122_MEMORYSTORE_OBSERVABILITY_CHECKLIST_CLOSURE_2026-06-17.md`

Ready for **Done**.
