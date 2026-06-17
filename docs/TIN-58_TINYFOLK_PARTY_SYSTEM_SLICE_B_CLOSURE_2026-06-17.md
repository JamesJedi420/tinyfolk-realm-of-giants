# TIN-58 Tinyfolk Party System — Slice B Closure

**Date:** 2026-06-17  
**Issue:** [TIN-58](https://linear.app/spectranoir/issue/TIN-58/implement-tinyfolk-party-system)  
**Related:** [TIN-125](https://linear.app/spectranoir/issue/TIN-125) (realm-status notify fanout, shipped TIN-59 Slice B), [TIN-57](https://linear.app/spectranoir/issue/TIN-57) (party hub anchor)

## Shipped

- **Disconnect grace (30s):** `TinyfolkPartyService` keeps party membership while a member is disconnected; grace expiry removes the member via `ResolveTransferOutcome`; reconnect within the window restores attributes without re-invite.
- **Transfer-outcome recovery:** `TinyfolkPartyState.ResolveTransferOutcome` + `HandleTransferOutcome` query seam for partial/full party splits after admission transfer.
- **Admission/teleport wiring:** `RealmAdmissionQueueProcessor` invokes `HandleTransferOutcome` after successful dispatch; skips resolver unregister when the party remains for recovery. `RealmTeleportDispatcher` excludes payload-failure members from teleport and returns `transferredUserIds` for partial callbacks.
- **Hub anchor (TIN-57):** Party panel F-key at `PartyHub_*` anchors (Slice B dependency satisfied on master).

## Validation

```powershell
.\scripts\run-validation.ps1 -ChangedOnly
lune run tests/tinyfolk_party_state.spec.luau
lune run tests/tinyfolk_party_service_runtime_entrypoint.spec.luau
lune run tests/realm_admission_queue_processor.spec.luau
lune run tests/realm_teleport_dispatcher_runtime_entrypoint.spec.luau
.\scripts\run-tests.ps1
```

## Acceptance mapping (TIN-58 Slice B)

| Criterion | Status |
|---|---|
| Disconnected party members handled safely | PASS — 30s grace holds membership; expiry removes |
| Partial transfer failure recovery | PASS — admission dispatch callbacks + payload-failure partial teleport |
| Party hub anchor / F-key | PASS (TIN-57) — `PartyHub_A` + interaction resolver |

## Deferred

- TIN-120 blind party matchmaking queue.
- Cross-server party persistence.
- Rich partial-failure client UX (notify copy beyond existing party snapshot fanout).
