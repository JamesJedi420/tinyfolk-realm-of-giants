# TIN-58 Tinyfolk Party System — Slice A (Create / Ready / Raid Board Queue) Kickoff

**Date:** 2026-06-16  
**Issue:** [TIN-58](https://linear.app/spectranoir/issue/TIN-58/implement-tinyfolk-party-system)  
**Milestone:** Admission and Queueing  
**Related:** [TIN-59](https://linear.app/spectranoir/issue/TIN-59) (raid board queue consumer), [TIN-57](https://linear.app/spectranoir/issue/TIN-57) (hub spawn), [TIN-117](https://linear.app/spectranoir/issue/TIN-117) (admission queue), [TIN-120](https://linear.app/spectranoir/issue/TIN-120) (matchmaking queue, deferred)

## Goal

Give Tinyfolk a **server-authoritative party lifecycle** in the shared hub so multiple players can queue for a selected Giant realm together. Slice A delivers create / invite / leave / ready-check and wires the raid board to real party identity instead of the solo `raid_board:{userId}` prototype path.

## Prerequisites

| Dependency | Status | Notes |
|---|---|---|
| TIN-59 raid board list + queue | **Done** | Solo queue via `RaidBoardHubService` + `raid_board:` prefix |
| TIN-117 admission queue | **Done** | `RealmAdmissionQueueService`, `PartyMatchmakingAdmissionService` |
| TIN-104 / TIN-105 teleport + registry | **Done** | Target realm resolution + reserved-server routing |
| TIN-11 transfer state | **Done** | `party_admission` transfer reason in `RealmTransferState` |
| `RealmAdmissionPartyResolverService` | **Done** | In-session party member registry + `RealmAdmissionPartyId` attribute fallback |

## Slice A boundary (in scope)

### Shared (pure)

- `TinyfolkPartyConfig` — remote names, cooldowns, max party size, attribute keys, `partyId` prefix (`tinyfolk_party:`).
- `TinyfolkPartyState` — deterministic validate/transition rules:
  - Party record: `partyId`, `leaderUserId`, `memberUserIds`, `readyUserIds`, `createdAt`, `updatedAt`.
  - Actions: `create`, `invite`, `accept_invite`, `leave`, `set_ready`, `clear_ready` (leader kick deferred).
  - Invariants: one active party per Tinyfolk; leader must be member; ready ⊆ members; all members ready before leader may queue (server gate).

### Server

- `TinyfolkPartyService.server.luau` bootstrap:
  - Ensures `ReplicatedStorage.Remotes` events for bounded party actions (create, invite, respond, leave, ready, snapshot notify).
  - Tinyfolk-only role gate on all handlers.
  - Session party store keyed by `partyId`; reverse index `partyIdByUserId`.
  - On membership change: update player attributes (`RealmAdmissionPartyId`, leader/ready flags for client projection).
  - Register resolved members via `_RealmAdmissionPartyResolver_QueryAPI.RegisterPartyMembers` / `UnregisterParty` on dissolve.
  - `_TinyfolkPartyService_QueryAPI` diagnostics + test seams (`GetPartySnapshot`, `ConfigureForTests`, `ResetForTests`).
- **`RaidBoardHubService` integration:**
  - Queue handler resolves requester's active party via `_TinyfolkPartyService_QueryAPI`.
  - If in party: require requester is leader, all members ready, enqueue with real `partyId` + full `partyMemberUserIds`.
  - If solo (no party): preserve existing `raid_board:{userId}` fallback for backward compatibility in Studio.
  - Reject with explicit reasons: `party_leader_required`, `party_not_ready`, `party_members_invalid`.

### Client

- `TinyfolkPartyClient.client.luau` — minimal hub UI (pattern: `RaidBoardClient`):
  - Create party, invite nearby Tinyfolk (or by user id list for prototype), accept/decline invite, leave, ready toggle.
  - Show leader, members, ready state; disable raid-board queue on non-leader clients (server still authoritative).
- Optional: hub map anchor / F-key for party panel deferred to Slice B (debug key or minimal ScreenGui button acceptable for Slice A).

## Out of scope / deferred

- Partial transfer failure recovery UX per member (Slice B).
- Disconnect / reconnect party rejoin rules (Slice B).
- TIN-120 blind party matchmaking queue (activity pick without target realm).
- Party-leader realm activity beyond raid-board target selection (scouting, rescue contract party flows).
- Cross-server party persistence (session-only for Slice A; `PartyHistoryProfileState` append remains on successful admission only).
- Hub safe-zone / capture-disable policy (TIN-57).
- Owner permission / invite-only realm discoverability (TIN-55).

## Data contracts

### Party snapshot (server → client)

```lua
{
  accepted: boolean,
  reason: string,
  partyId: string?,
  leaderUserId: number?,
  memberUserIds: { number }?,
  readyUserIds: { number }?,
  pendingInviteUserIds: { number }?,
  updatedAt: number?,
}
```

**Must not expose:** handoff tokens, private server ids, job ids.

### Raid board queue with party (server validation)

| Check | Reason on failure |
|---|---|
| Requester has `Role == Tinyfolk` | `role_not_tinyfolk` (existing) |
| In party → requester is leader | `party_leader_required` |
| In party → all members ready | `party_not_ready` |
| In party → member list matches resolver | `party_members_invalid` |
| Target realm still queueable | `target_realm_unavailable` (existing) |

Enqueue still flows through `_PartyMatchmakingAdmissionService_QueryAPI.RequestPartyMatchAdmission` with `partyMemberUserIds` matching `partySize`.

## Queue semantics (Slice A)

- **Solo fallback:** no active party → `partyId = "raid_board:" .. userId`, `partyMemberUserIds = { userId }` (unchanged from TIN-59 Slice A).
- **Party path:** `partyId = "tinyfolk_party:" .. leaderUserId .. ":" .. createdAt` (or deterministic id from `TinyfolkPartyState`; prefix avoids collision with `raid_board:` namespace).
- **Ready gate:** leader queue action rejected until `readyUserIds` contains every `memberUserIds` entry.
- **Post-enqueue:** existing queue processor + `RealmTeleportDispatcher` handle transfer; no new dispatch code in TIN-58 Slice A.

## Key files to inspect first

| Area | Path |
|---|---|
| Admission party resolver | `src/ServerScriptService/Services/RealmAdmissionPartyResolverService.luau` |
| Party match admission | `src/ServerScriptService/Services/PartyMatchmakingAdmissionService.server.luau` |
| Queue validation | `src/ReplicatedStorage/Shared/GiantRealm/RealmAdmissionQueueState.luau` |
| Raid board queue | `src/ServerScriptService/Services/RaidBoardHubService.server.luau` |
| Teleport party members | `src/ServerScriptService/Services/RealmTeleportDispatcher.luau` |
| Party history (post-admission) | `src/ReplicatedStorage/Shared/GiantRealm/PartyHistoryProfileState.luau` |
| Client UI precedent | `src/StarterPlayer/StarterPlayerScripts/Client/RaidBoardClient.client.luau` |
| Tests | `tests/realm_admission_party_resolver_service_runtime_entrypoint.spec.luau`, `tests/party_matchmaking_admission_service_runtime_entrypoint.spec.luau`, `tests/raid_board_hub_service_runtime_entrypoint.spec.luau` |

## Acceptance criteria mapping (TIN-58)

| Linear criterion | Slice A plan |
|---|---|
| Tinyfolk can create a party | `create` remote + `TinyfolkPartyState` |
| Party leader can select eligible realm activity | Raid board queue restricted to leader when in party |
| All members must be ready before transfer | Server `party_not_ready` gate before enqueue |
| Party transfer creates pending record per member | Existing admission queue + handoff path (no new producer) |
| Disconnected party members handled safely | **Deferred Slice B** |
| Partial transfer failure recovery | **Deferred Slice B** |

## Validation

```powershell
.\scripts\run-validation.ps1 -ChangedOnly
lune run tests/tinyfolk_party_state.spec.luau
lune run tests/tinyfolk_party_service_runtime_entrypoint.spec.luau
lune run tests/realm_admission_party_resolver_service_runtime_entrypoint.spec.luau
lune run tests/party_matchmaking_admission_service_runtime_entrypoint.spec.luau
lune run tests/raid_board_hub_service_runtime_entrypoint.spec.luau
.\scripts\run-tests.ps1
```

## Risks

| Risk | Mitigation |
|---|---|
| `raid_board:` vs `tinyfolk_party:` namespace collision | Distinct prefixes; migrate raid board to party resolver when member present |
| Ready-state desync on invite mid-queue | Clear ready on membership change; re-validate on queue |
| Solo Studio workflows break | Keep solo fallback when not in party |
| Over-scoping disconnect recovery | Explicit Slice B deferral; Slice A happy-path only |

## Follow-up slices (not Slice A)

- **TIN-58 Slice B:** disconnect/reconnect, partial transfer failure, party panel hub anchor (TIN-57).
- **TIN-120:** shared matchmaking queue without pre-selected realm.
- **TIN-55:** invite-only realm discoverability for party invites.
