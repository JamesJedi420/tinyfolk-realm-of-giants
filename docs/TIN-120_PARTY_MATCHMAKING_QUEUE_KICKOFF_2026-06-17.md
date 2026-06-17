# TIN-120 Party Matchmaking Queue — Kickoff

**Date:** 2026-06-17  
**Issue:** [TIN-120](https://linear.app/spectranoir/issue/TIN-120/implement-party-matchmaking-queue)  
**Milestone:** Admission and Queueing  
**Related:** [TIN-58](https://linear.app/spectranoir/issue/TIN-58) (party leader semantics), [TIN-117](https://linear.app/spectranoir/issue/TIN-117) (realm admission queue), [TIN-59](https://linear.app/spectranoir/issue/TIN-59) (raid board target-selected queue)

## Goal

Let Tinyfolk parties queue for shared hub activities **before** a target realm is selected. Matched parties receive realm candidates and flow into the existing admission queue; unmatched or expired parties return to normal hub state.

## In scope

### Shared

- `PartyMatchmakingQueueConfig` — activities (`raid`, `rescue`, `scouting`, `work_contract`), remotes, cooldowns, timeout bounds, `raid_board:` namespace guard.
- `PartyMatchmakingQueueState` — bounded entry contract (`partyId`, `leaderUserId`, `partySize`, `partyMemberUserIds`, `desiredActivity`, `skillBand`, `toolTier`, `expiration`, status transitions).
- `LiveRealmHubRouting.SelectMatchmakingTarget` — activity-aware realm candidate selection from live registry availability.

### Server

- `PartyMatchmakingQueueStore` — MemoryStore queue producer for `partyMatchmakingQueue` policy.
- `PartyMatchmakingQueueProcessor` — hub polling processor: expiry, party-size/member revalidation, match, admission handoff via `_PartyMatchmakingAdmissionService_QueryAPI.RequestPartyMatchAdmission`.
- `PartyMatchmakingQueueService` — enqueue/read/process/query seams (`_PartyMatchmakingQueue_QueryAPI`).
- `PartyMatchmakingHubService` — hub remotes for enqueue + poll; party leader/ready gates via `_TinyfolkPartyService_QueryAPI.ResolveMatchmakingQueueContext`.
- `TinyfolkPartyState.ValidateMatchmakingQueue` + `TinyfolkPartyService.ResolveMatchmakingQueueContext`.

## Out of scope

- Cross-server party persistence.
- TIN-14 hub district growth.
- Rich matchmaking UX polish (skillBand/toolTier tuning, animations).
- Rescue contract board discoverability UI (alternate product path).

## Client slice (2026-06-17 follow-up)

- `PartyMatchmakingHubPresentation` — deterministic status/activity copy for enqueue, poll, and notify payloads.
- `PartyMatchmakingClient` — wires `PartyMatchmakingEnqueueRequest` / `PollRequest` / `Notify` with activity pick, join queue, and pending poll loop.
- `InteractionResolver` — F-key opens matchmaking panel via `PartyMatchmakingOpenRequested` at `PartyMatchmakingHub_*` anchors.
- `TinyfolkPartyClient` — party panel **Open Matchmaking** button sets the same open attribute.
- Map anchor `PartyMatchmakingHub_A` in `TinyfolkWorld` hub district.

## Queue semantics

| Path | Contract |
|---|---|
| Blind matchmaking (`TIN-120`) | Activity pick only; `partyId` must not use `raid_board:` namespace |
| Raid board solo (`TIN-59`) | `raid_board:{userId}` with explicit `targetRealmId` — unchanged |
| Party raid board (`TIN-58`) | `tinyfolk_party:*` with explicit `targetRealmId` — unchanged |

**Idempotency:** one pending queue entry per `partyId` on the hub server session map; duplicate enqueue returns `party_already_queued`. Processor revalidates member list/size before match; drift expires with `party_members_changed`.

## Validation

```powershell
.\scripts\run-validation.ps1 -ChangedOnly
lune run tests/party_matchmaking_hub_presentation.spec.luau
lune run tests/party_matchmaking_queue_state.spec.luau
lune run tests/party_matchmaking_queue_service_runtime_entrypoint.spec.luau
lune run tests/party_matchmaking_hub_service_runtime_entrypoint.spec.luau
lune run tests/tinyfolk_party_service_runtime_entrypoint.spec.luau
lune run tests/party_matchmaking_admission_service_runtime_entrypoint.spec.luau
.\scripts\run-tests.ps1
```

## Acceptance mapping

| Criterion | Plan |
|---|---|
| Enter shared matchmaking queue | `PartyMatchmakingHubService` enqueue remote |
| Store partyId, partySize, desiredActivity, skillBand, toolTier, timeout | `PartyMatchmakingQueueState` + enqueue contract |
| Lobby reads queue periodically | `PartyMatchmakingQueueService` processing loop + `ReadBatch` |
| Matched parties receive target realm candidates | Processor match + admission enqueue + poll snapshot `targetRealmId` |
| Unmatched/expired return to hub state | Expiry transitions + poll/notify `queue_resolved` |
