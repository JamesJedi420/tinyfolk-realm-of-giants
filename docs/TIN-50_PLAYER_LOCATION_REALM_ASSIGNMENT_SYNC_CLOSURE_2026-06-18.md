# TIN-50 Player Location ↔ Realm Assignment Sync — Closure

**Date:** 2026-06-18  
**Issue:** [TIN-50](https://linear.app/spectranoir/issue/TIN-50/implement-global-player-location-state-machine) (follow-up slice B)  
**Milestone:** Admission and Queueing  
**Kickoff:** `docs/TIN-50_PLAYER_LOCATION_REALM_ASSIGNMENT_SYNC_KICKOFF_2026-06-18.md`  
**PR:** [#132](https://github.com/JamesJedi420/tinyfolk-realm-of-giants/pull/132)

## Shipped

- **`PlayerLocationAssignmentSync`** — pure mapping between `PlayerLocationState` operations and `RealmTransferState` assignment operations, plus idempotent transit-pair matching.
- **`PlayerLocationAssignmentSyncCaller`** — coupled apply for location + `realmAssignment` with ignorable idempotent reasons (`transfer_already_in_flight`, `already_in_transit`).
- **`RealmAdmissionLocationCaller`** — begin / confirm / abort routes through sync caller so admission queue paths keep both models aligned.
- **`PlayerLocationTransitionCaller`** — hub-return and escape-return paths sync assignment clears (`set_shared_hub` / `confirm_hub_return`).
- **`ProfileTeleportHandoffService`** — arrival confirm uses coupled confirm only (removed duplicate assignment confirm call).
- Custody substates (`capture`, `contain`, `begin_escape`, `escape_failed`) remain session-only and do not mutate durable assignment.

## Validation

```powershell
.\scripts\run-validation.ps1 -ChangedOnly
lune run tests/player_location_assignment_sync.spec.luau
lune run tests/player_location_assignment_sync_caller_runtime_entrypoint.spec.luau
lune run tests/player_location_state.spec.luau
lune run tests/player_location_service_runtime_entrypoint.spec.luau
lune run tests/profile_teleport_handoff_service_runtime_entrypoint.spec.luau
.\scripts\run-tests.ps1
```

Local rerun on 2026-06-18: all commands passed before merge.

## Acceptance mapping

| Criterion | Status | Implementation |
|---|---|---|
| Admission begin sets transit + transfer_in_flight | PASS | `RealmAdmissionLocationCaller.ApplyBeginForAdmission` → sync caller |
| Admission confirm sets realm location + giant_realm assignment | PASS | `ApplyCoupledConfirmForArrival` |
| Admission abort clears both models | PASS | `ApplyCoupledAbortRollback` |
| Escape success / hub clear clears assignment | PASS | `PlayerLocationTransitionCaller` + `set_shared_hub` mapping |
| Custody transitions do not mutate assignment | PASS | nil mapping for capture/contain/escape ops |
| Teleport arrival is single coupled confirm path | PASS | `ProfileTeleportHandoffService.finalizeArrivalConfirmations` |
| Pure mapping test-backed | PASS | `tests/player_location_assignment_sync.spec.luau` |

## Deferred (unchanged)

- Retiring `pendingRecovery` legacy derivation.
- `RealmSafeReturnService` full rewire (existing paired location + `abort_to_hub` hooks remain).
- Published-client TIN-107 four-flow evidence.
- New `realmAssignment` categories for every custody substate.

## Issue boundary assessment

| TIN-50 original deferred item | Met by this slice? |
|---|---|
| Wire admission/teleport consumers to location transitions | **Yes** (slice A + prior PR #128; this slice adds assignment parity) |
| Consolidate `realmAssignment` with runtime custody states | **Partial** — coarse assignment sync on transfer paths; custody substates stay session-only by design |
| Published-client disconnect/reconnect spot-check | **No** — remains operator/TIN-107 |

**Recommendation:** Keep TIN-50 **In Progress** until TIN-107 published evidence completes, or split remaining TIN-107/TIN-50 follow-ups into explicit issues.
