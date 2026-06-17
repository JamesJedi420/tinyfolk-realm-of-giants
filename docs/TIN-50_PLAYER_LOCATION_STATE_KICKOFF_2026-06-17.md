# TIN-50 Player Location State Machine - Kickoff

**Date:** 2026-06-17  
**Issue:** [TIN-50](https://linear.app/spectranoir/issue/TIN-50/implement-global-player-location-state-machine)  
**Milestone:** Admission and Queueing  
**Related:** [TIN-11](https://linear.app/spectranoir/issue/TIN-11), [TIN-49](https://linear.app/spectranoir/issue/TIN-49)

## Goal

Add a server-authoritative, session-runtime player location state machine that prevents broken transfers and trapped players without rewiring every transfer service in one slice.

## In scope

- Canonical location states: `shared_hub`, `realm_guest`, `realm_invader`, `captured`, `contained`, `escaping`, `transit`, `disconnected_in_realm`, `return_pending`.
- Pure deterministic transition resolver in `Shared/GiantRealm/PlayerLocationState`.
- Ephemeral session registry and query seam in `PlayerLocationService` (no durable persistence writes).
- Safe disconnect resolution policy for in-realm and in-transit players.
- Bridge helper to derive initial runtime location from existing `realmAssignment` snapshots.

## Out of scope

- Full cross-server queueing and teleport orchestration rewires.
- Durable persistence migration for location state.
- Capture/containment/escape service integration beyond query seams.

## Acceptance mapping

| Criterion | Target |
|---|---|
| Exactly one active location state per player | `PlayerLocationService.GetLocationSnapshot` |
| Invalid transitions rejected | `PlayerLocationState.ResolveTransition` |
| Captured -> Escaping or ReturnPending | `begin_escape`, `set_return_pending` operations |
| Disconnected players resolve safely | `PlayerLocationState.ResolveDisconnect` |
| Testable state machine | `tests/player_location_state.spec.luau` |

## Validation

```powershell
.\scripts\run-validation.ps1 -ChangedOnly
lune run tests/player_location_state.spec.luau
lune run tests/player_location_service_runtime_entrypoint.spec.luau
```

## Deferred

- Wire capture, escape, admission, and teleport services to consume location transitions.
- Published-client multi-server disconnect/reconnect spot-check.
- Consolidate `realmAssignment` location categories with runtime custody states.
