# TIN-50 Player Location State Machine - Closure

**Date:** 2026-06-17  
**Issue:** [TIN-50](https://linear.app/spectranoir/issue/TIN-50/implement-global-player-location-state-machine)  
**Milestone:** Admission and Queueing  
**Status:** Closed slice

## Shipped

- **Canonical runtime location states:** `PlayerLocationState` defines `shared_hub`, `realm_guest`, `realm_invader`, `captured`, `contained`, `escaping`, `transit`, `disconnected_in_realm`, and `return_pending`.
- **Transition policy:** `PlayerLocationState.ResolveTransition` validates ingress, custody, escape, return, and disconnect-mark transitions with deterministic reject reasons.
- **Safe disconnect resolution:** `PlayerLocationState.ResolveDisconnect` routes in-realm and in-transit players to `return_pending` (or hub for escape-return transit) without durable persistence writes.
- **Session registry seam:** `PlayerLocationService` exposes `_PlayerLocationService_QueryAPI` for snapshot, transition, disconnect, hydrate-from-assignment, and diagnostics.
- **Realm assignment bridge:** `DeriveFromRealmAssignment` maps existing `realmAssignment` categories into runtime location snapshots.

## Validation

```powershell
.\scripts\run-validation.ps1 -ChangedOnly
lune run tests/player_location_state.spec.luau
lune run tests/player_location_service_runtime_entrypoint.spec.luau
```

Local rerun on 2026-06-17: all commands passed.

## Acceptance mapping

| Criterion | Status | Implementation |
|---|---|---|
| Every player has exactly one active location state | PASS | `PlayerLocationService.GetLocationSnapshot` |
| Invalid transitions rejected | PASS | `PlayerLocationState.ResolveTransition` |
| Captured -> Escaping or ReturnPending | PASS | `begin_escape`, `set_return_pending` |
| Disconnected players resolve safely | PASS | `PlayerLocationState.ResolveDisconnect` |
| State machine is testable | PASS | focused Lune specs |

## Deferred

- Wire capture, escape, admission, and teleport services to consume location transitions.
- Published-client disconnect/reconnect spot-check.
- Consolidate `realmAssignment` location categories with runtime custody states.
