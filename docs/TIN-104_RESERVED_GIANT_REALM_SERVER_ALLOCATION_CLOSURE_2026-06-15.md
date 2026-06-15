# TIN-104 Reserved Giant Realm Server Allocation — Closure

## Status

- Issue: [TIN-104](https://linear.app/spectranoir/issue/TIN-104/implement-reserved-giant-realm-server-allocation)
- Milestone: Admission and Queueing
- Implemented: 2026-06-15 (local validation clean; PR pending)

## Shipped

- `RealmReservedServerAllocationState` — allocation record validation, stable-placeholder detection, idempotent ensure rules, save/mirror encode-decode, `ValidateDispatchAdmission` (`standard` entry requires public `accessMode`).
- `GiantRealmSaveSchema` — optional `realmServerAllocation` on save root; validate/serialize through existing build/apply paths.
- `LiveRealmHubRouting` — `ResolveTeleportAccessCode(snapshot, reservedAccessCode?)` with detailed resolver paths: live registry (non-placeholder) → durable allocation → unresolved; cold-start path when hub snapshot missing but mirror code + owner valid.
- `MemoryStoreStructurePolicy.realmReservedServerAllocation` — HashMap mirror keyed by `realmId`.
- `RealmReservedServerAllocationStore` — publish/read adapter seam with in-memory fallback.
- `RealmReservedServerAllocationService` + bootstrap — `EnsureAllocation` (ReserveServer once, persist profile, publish mirror), `ResolveAccessCodeForRealm`, persistence apply/build, `_RealmReservedServerAllocationService_QueryAPI`.
- `RoleService` — calls `EnsureAllocation` after successful Giant realm profile load.
- `GiantBuildModeService` — wires allocation into save snapshot apply/build.
- `RealmTeleportDispatcher` — resolves access code via hub routing + allocation mirror; **removed per-dispatch `ReserveServer` fallback** for known `targetRealmId`; validates entry type vs access mode.
- `LiveRealmRegistryService` — heartbeat publish prefers live PS id, else allocation-backed code over stable placeholder.

## Validation

```powershell
.\scripts\run-validation.ps1 -ChangedOnly
lune run tests/realm_reserved_server_allocation_state.spec.luau
lune run tests/realm_reserved_server_allocation_service_runtime_entrypoint.spec.luau
lune run tests/live_realm_hub_routing.spec.luau
lune run tests/realm_teleport_dispatcher_runtime_entrypoint.spec.luau
lune run tests/live_realm_registry_service.spec.luau
lune run tests/giant_realm_save_schema.spec.luau
lune run tests/memorystore_structure_policy.spec.luau
.\scripts\run-tests.ps1
rojo sourcemap default.project.json -o sourcemap.json
```

All commands passed locally on 2026-06-15.

## Edge cases (by design)

| Scenario | Behavior |
|---|---|
| Hub join before Giant ever loads | Dispatch fails `reserved_server_unallocated` (retryable) |
| Hub unavailable + mirror allocation present | Cold-start routing via durable code + parsed owner |
| Public realm with stable placeholder | Uses persisted/mirror reserved code, not `ReserveServer` |

## Unblocks

- **TIN-59 Slice A** — raid-board queue → teleport can rely on stable reserved access codes instead of ephemeral `ReserveServer` per join.

## Deferred

- Published-client teleport evidence (TIN-107) — Studio/live verification after merge.
- Full permission matrix UI (TIN-55).
