# TIN-105 Live Realm Registry Closure

## Status

- Issue: [TIN-105](https://linear.app/spectranoir/issue/TIN-105/implement-active-realm-instance-registry)
- Milestone: Admission and Queueing
- Closed: 2026-06-15

## Shipped

- `LiveRealmRegistryState` — deterministic registry entry validation, lifecycle/access-mode rules, encode/decode, availability snapshots (`realmId` distinct from `jobId`; stable `privateServerId` fallback).
- `LiveRealmRegistryStore` — MemoryStore sorted-map publish/refresh/prune/list with in-memory fallback.
- `LiveRealmRegistryService` + bootstrap — publish/refresh/prune heartbeat, diagnostics, `_LiveRealmRegistry_QueryAPI`, `_LiveRealmRegistryHubSurface_QueryAPI`.
- `MemoryStoreAdapter` — bounded `SortedMap*` operations for `liveRealmRegistry`.
- `QueueNotificationFanout.PublishRealmStatus` — best-effort `realm_status_changed` hints on `tin_realm_v1`.
- `RoleService` — publish on Giant realm profile load; prune on save/release and server shutdown.
- `NotificationReconciliationService.ReconcileRealmStatus` — prefers live registry hub availability reads with metadata-registry fallback.

## Validation

```powershell
.\scripts\run-validation.ps1 -ChangedOnly
lune run tests/live_realm_registry_state.spec.luau
lune run tests/live_realm_registry_store.spec.luau
lune run tests/live_realm_registry_service.spec.luau
lune run tests/memorystore_structure_policy.spec.luau
.\scripts\run-tests.ps1
```

All commands passed locally on 2026-06-15.

## Deferred

- Full raid-board UX (out of slice scope).
- Bridge session conversion ledger → `giantRealmResourcePersistence` (TIN-29/TIN-64 follow-up).
