# TIN-59 Shared Raid Board — Slice A (Client/Hub Presentation) Kickoff

**Date:** 2026-06-15  
**Issue:** [TIN-59](https://linear.app/spectranoir/issue/TIN-59/implement-shared-raid-board)  
**Milestone:** Admission and Queueing  
**Related:** [TIN-105](https://linear.app/spectranoir/issue/TIN-105) (availability seam), [TIN-104](https://linear.app/spectranoir/issue/TIN-104) (public join semantics), [TIN-117](https://linear.app/spectranoir/issue/TIN-117) (admission queue), [TIN-58](https://linear.app/spectranoir/issue/TIN-58) (party system, deferred)

## Goal

Give Tinyfolk a bounded hub raid-board surface to **browse** discoverable Giant realms and **queue** for a selected realm using the existing live-registry availability seam and admission-queue path. This slice is presentation + server-gated client remotes only; it does not add new matchmaking, registry, or teleport routing logic.

## Prerequisites

| Dependency | Status | Notes |
|---|---|---|
| TIN-105 live registry + hub read wiring | **Done** | `_LiveRealmRegistryHubSurface_QueryAPI.ListLiveRealmAvailability`, `LiveRealmHubRouting` |
| TIN-104 reserved public-realm join | **Blocked / next** | Public realms with only `giant_realm_ps_*` fallback currently fail teleport (`ReserveServer` fallback). **Do not ship raid-board queue UX to published clients until TIN-104 lands**, or gate queue action behind server rejection with explicit reason. |
| TIN-117 admission queue | **Done** | `RealmAdmissionQueueService.EnqueueAdmission`, `PartyMatchmakingAdmissionService` |
| TIN-58 party system | **Backlog** | Slice A uses deterministic solo `partyId` (see Queue semantics). |

## Slice A boundary (in scope)

### Shared (pure)

- `RaidBoardConfig` — remote names, request cooldown, list limit, refresh coalesce window, prototype reward-tier buckets from `dangerRating`.
- `RaidBoardHubState` — deterministic filter/sort/project rules:
  - Input: registry availability snapshots (+ optional owner display names supplied by server).
  - Output: client-safe listing rows (no `privateServerId`, no `jobId`).
  - Discoverability: include only `accessMode == public` and `isAvailable == true`.
  - Hide `private` and `invite_only` rows (no invite-token path in this slice).
  - Sort: `dangerRating` desc, then `realmId` asc (match `LiveRealmRegistryService.ListLiveRealmAvailability`).

### Server

- `RaidBoardHubService.server.luau` bootstrap:
  - Ensures `ReplicatedStorage.Remotes` events: `RaidBoardListRequest`, `RaidBoardListResponse`, `RaidBoardQueueRequest`, `RaidBoardQueueResponse`, `RaidBoardNotify` (optional hint fanout).
  - `List` handler: Tinyfolk-only, per-player rate limit, reads `_LiveRealmRegistryHubSurface_QueryAPI`, projects via `RaidBoardHubState`, resolves owner display labels (bounded cache; fallback `Giant {ownerUserId}`).
  - `Queue` handler: Tinyfolk-only, validates `targetRealmId` against projected listing (or re-validates via `LiveRealmHubRouting.ResolveAdmissionTarget`), enqueues through `_PartyMatchmakingAdmissionService_QueryAPI.RequestPartyMatchAdmission` with `entryType` path using `standard` queue priority.
  - Diagnostics: `_RaidBoardHubService_QueryAPI.GetDiagnostics` (list/queue attempts, last reason, last resolver path).
- No changes to `LiveRealmRegistryService`, `RealmTeleportDispatcher`, or MemoryStore structures.

### Client

- `RaidBoardClient.client.luau` — minimal ScreenGui (pattern: `VillageUpgradeHubClient`):
  - Open/close board (keyboard debug bind acceptable for prototype; map anchor polish deferred).
  - On open: fire list request; render rows (owner, danger, population/capacity, entry type, prototype reward tier).
  - Row action: queue for selected `realmId`; show server reason on failure.
  - Refresh: on open + on `RaidBoardNotify` + manual refresh button; client-side coalesce (config window) to avoid request spam.
- `RaidBoardHubPresentation` (optional thin shared formatter) if projection formatting is non-trivial.

## Out of scope / deferred

- Authored hub map anchor / world prop for the board (TIN-57).
- Full party leader flow, invite gating, ready-check UI (TIN-58).
- Realm permission settings UI (TIN-55); server respects current registry `accessMode` only.
- Reward economy balancing, defended-raid producer hooks, treasury display (TIN-64).
- Custom realm names from durable save / metadata theme selection (no `realmName` on availability snapshot yet).
- `invite_only` discoverability and direct-invite deep links.
- MessagingService subscription wiring beyond optional notify remote (TIN-125 full reconciliation is separate).
- F-key hub interaction anchor; debug key + ScreenGui is sufficient for Slice A.

## Data contracts

### Client-safe listing row (`RaidBoardListingRow`)

| Field | Type | Source |
|---|---|---|
| `realmId` | string | registry snapshot |
| `ownerUserId` | number | registry snapshot |
| `ownerDisplayName` | string | server-resolved; never client-supplied |
| `dangerRating` | number | registry snapshot (0–1) |
| `playerCount` | number | registry snapshot |
| `capacity` | number | registry snapshot |
| `accessMode` | string | registry snapshot (`public` only after filter) |
| `entryTypeLabel` | string | prototype map: `public` → `"Raid"` |
| `rewardTierLabel` | string | prototype bucket from `dangerRating` (config thresholds) |
| `isQueueable` | boolean | `isAvailable` and hub routing accepts direct target |
| `updatedAt` | number | registry snapshot |

**Must not expose:** `privateServerId`, `jobId`, live server codes, handoff tokens.

### List request / response

```lua
-- Request (client → server)
{ requestId: string, limit: number? }

-- Response (server → client, FireClient)
{
  requestId: string,
  accepted: boolean,
  reason: string,
  listings: { RaidBoardListingRow }?,
  refreshedAt: number?,
}
```

### Queue request / response

```lua
-- Request
{ requestId: string, targetRealmId: string }

-- Response
{
  requestId: string,
  accepted: boolean,
  reason: string, -- e.g. accepted, target_realm_unavailable, role_not_tinyfolk, rate_limited
  targetRealmId: string?,
  queueSnapshot: { operationId: string, partyId: string }?, -- bounded, no secrets
}
```

## Queue semantics (Slice A)

- **Role gate:** requester must have `Role == "Tinyfolk"` (server attribute).
- **Solo prototype party:** `partyId = "raid_board:" .. userId`, `partyMemberUserIds = { userId }`.
- **Entry type:** enqueue with `entryType = "standard"` (existing `RealmAdmissionQueueState` priority).
- **Target resolution:** require explicit `targetRealmId` from listing; no blind raid-board auto-pick on client (server already supports auto-pick via `LiveRealmHubRouting` for other consumers — not exposed in Slice A UI).
- **Re-validation:** server calls `LiveRealmHubRouting.ResolveAdmissionTarget({ targetRealmId }, availability)` before enqueue.
- **Admission API:** `_PartyMatchmakingAdmissionService_QueryAPI.RequestPartyMatchAdmission`.
- **Post-enqueue:** existing queue processor + teleport dispatcher handle transfer; no new dispatch code in TIN-59.

## Refresh model

1. **Authoritative read:** MemoryStore registry via `_LiveRealmRegistryHubSurface_QueryAPI` (not client-cached registry).
2. **Hint path:** optional `RaidBoardNotify` after `NotificationReconciliationService.ReconcileRealmStatus` (best-effort; listing still valid if notify missed).
3. **Rate limits:** per-player cooldown on list + queue (config, mirror `RansomBoardConfig.RequestCooldownSeconds` pattern).
4. **Coalesce:** client ignores duplicate list requests inside coalesce window; server rejects rapid-fire with `rate_limited`.

## Key files to inspect first

| Area | Path |
|---|---|
| Availability seam | `src/ServerScriptService/Services/LiveRealmRegistryBootstrap.server.luau` |
| Hub routing | `src/ReplicatedStorage/Shared/GiantRealm/LiveRealmHubRouting.luau` |
| Registry snapshots | `src/ReplicatedStorage/Shared/GiantRealm/LiveRealmRegistryState.luau` |
| Party admission | `src/ServerScriptService/Services/PartyMatchmakingAdmissionService.server.luau` |
| Queue entry types | `src/ReplicatedStorage/Shared/GiantRealm/RealmAdmissionQueueState.luau` |
| Hub board precedent | `src/ServerScriptService/Services/RescueContractService.server.luau` (`_RescueContractHubSurface_QueryAPI`) |
| Client hub UI precedent | `src/StarterPlayer/StarterPlayerScripts/Client/VillageUpgradeHubClient.client.luau` |
| Remote board precedent | `src/StarterPlayer/StarterPlayerScripts/Client/RansomBoardClient.client.luau` |
| Tests | `tests/live_realm_hub_routing.spec.luau`, `tests/party_matchmaking_realm_resolver_service_runtime_entrypoint.spec.luau` |

## Acceptance criteria mapping (TIN-59)

| Linear criterion | Slice A plan |
|---|---|
| Raid board lists eligible realms | List remote + `RaidBoardHubState` filter (`public`, available) |
| Listing includes realm name, owner, danger, reward, entry type | `ownerDisplayName`, `dangerRating`, `rewardTierLabel` (prototype), `entryTypeLabel`; realm name = `ownerDisplayName .. "'s Realm"` until durable naming exists |
| Locked/private realms hidden unless invited | Hide non-`public`; invite path deferred |
| Tinyfolk can queue for selected realm | Queue remote → `RequestPartyMatchAdmission` |
| Listings refresh safely | Rate limit + coalesce + optional notify hint |

## Validation

```powershell
.\scripts\run-validation.ps1 -ChangedOnly
lune run tests/raid_board_hub_state.spec.luau
lune run tests/raid_board_hub_service_runtime_entrypoint.spec.luau
lune run tests/live_realm_hub_routing.spec.luau
lune run tests/party_matchmaking_admission_service_runtime_entrypoint.spec.luau
.\scripts\run-tests.ps1
```

## Risks

| Risk | Mitigation |
|---|---|
| Queue succeeds but teleport fails for public stable fallback | **Hard dependency on TIN-104**; integration test after TIN-104 merges |
| Owner display name fetch latency | Bounded cache; fallback numeric label |
| Solo `partyId` collides with future TIN-58 parties | Prefix namespace `raid_board:`; migrate in TIN-58 slice |
| Client spam on hub | Server cooldown + client coalesce |
| Over-exposing registry internals | Pure projection module + spec asserting forbidden fields absent |

## Follow-up slices (not Slice A)

- **TIN-59 Slice B:** map anchor, F-key interaction, richer reward/danger presentation, party-leader queue (TIN-58).
- **TIN-104:** public-realm reserved-server join semantics (teleport path).
- **TIN-55:** owner-controlled access modes beyond registry defaults.
