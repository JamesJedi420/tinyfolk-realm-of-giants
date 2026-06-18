# TIN-50 Player Location ↔ Realm Assignment Sync — Kickoff

**Date:** 2026-06-18  
**Issue:** [TIN-50](https://linear.app/spectranoir/issue/TIN-50/implement-global-player-location-state-machine) (follow-up slice B)  
**Milestone:** Admission and Queueing  
**Related:** [TIN-11](https://linear.app/spectranoir/issue/TIN-11), [TIN-49](https://linear.app/spectranoir/issue/TIN-49), [TIN-107](https://linear.app/spectranoir/issue/TIN-107)

## Goal

Keep session runtime location (`PlayerLocationService`) and durable `realmAssignment` (`RealmTransferAssignmentService`) aligned on overlapping transfer transitions so admission, teleport, and custody paths do not drift.

## Problem

- TIN-50 added runtime location with hydrate-from-assignment only (read bridge).
- TIN-11 added durable `realmAssignment` transitions on teleport handoff.
- Admission and custody callers updated one model without the other, risking mismatched `transfer_in_flight` vs `transit` or `giant_realm` vs `realm_guest` reads.

## In scope

### Shared

- `PlayerLocationAssignmentSync` — pure operation mapping between `PlayerLocationState` and `RealmTransferState` transitions; idempotent match helpers for already-synced pairs.

### Server

- `PlayerLocationAssignmentSyncCaller` — coupled apply with best-effort rollback when the paired transition fails.
- `RealmAdmissionLocationCaller` — begin / confirm / abort routes through sync caller.
- `PlayerLocationTransitionCaller` — hub-return and escape-return paths sync assignment clears.
- `ProfileTeleportHandoffService` — arrival confirm uses sync caller instead of separate location + assignment calls.

## Out of scope

- New `realmAssignment` categories for custody substates (`captured`, `contained`, `escaping` remain session-only).
- Retiring `pendingRecovery` legacy derivation.
- `RealmSafeReturnService` full rewire (uses existing paired location + abort assignment hooks).
- Published-client TIN-107 evidence.

## Sync contract

| Location operation | Assignment operation | Notes |
|---|---|---|
| `begin_transit` | `begin_*` from transit reason | Skip when assignment already in matching flight |
| `abort_transit` + `resolve_hub` | `abort_to_hub` | Admission rollback |
| `confirm_realm_guest` / `confirm_realm_invader` | `confirm_arrival` | |
| `confirm_captured` | `confirm_arrival` | |
| `confirm_hub_return` | `confirm_hub_return` | |
| `escape_succeeded` / `resolve_hub` (clear realm) | `set_shared_hub` | |
| `capture`, `contain`, `begin_escape`, `escape_failed` | none | Session custody only |

## Validation

```powershell
.\scripts\run-validation.ps1 -ChangedOnly
lune run tests/player_location_assignment_sync.spec.luau
lune run tests/player_location_assignment_sync_caller_runtime_entrypoint.spec.luau
lune run tests/player_location_state.spec.luau
lune run tests/player_location_service_runtime_entrypoint.spec.luau
lune run tests/realm_transfer_state.spec.luau
lune run tests/realm_transfer_assignment_service_runtime_entrypoint.spec.luau
lune run tests/profile_teleport_handoff_service_runtime_entrypoint.spec.luau
.\scripts\run-tests.ps1
```

## Acceptance mapping

| Criterion | Target |
|---|---|
| Admission begin sets both transit + transfer_in_flight | `RealmAdmissionLocationCaller` + sync caller |
| Admission confirm sets realm location + giant_realm assignment | coupled confirm |
| Admission abort clears both | coupled abort |
| Escape return / hub clear clears assignment | `PlayerLocationTransitionCaller` |
| Teleport arrival confirm is single coupled path | `ProfileTeleportHandoffService` |
| Custody transitions do not mutate assignment | mapping returns nil |
| Pure mapping is test-backed | `player_location_assignment_sync.spec.luau` |
