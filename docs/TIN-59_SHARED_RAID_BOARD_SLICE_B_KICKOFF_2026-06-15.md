# TIN-59 Shared Raid Board — Slice B (Hub Anchor + Notify Hints) Kickoff

**Date:** 2026-06-15  
**Issue:** [TIN-59](https://linear.app/spectranoir/issue/TIN-59/implement-shared-raid-board)  
**Milestone:** Admission and Queueing  
**Related:** [TIN-57](https://linear.app/spectranoir/issue/TIN-57) (hub map anchor / F-key), [TIN-125](https://linear.app/spectranoir/issue/TIN-125) (notification reconciliation fanout), [TIN-58](https://linear.app/spectranoir/issue/TIN-58) (party system, deferred)

## Goal

Make the Slice A raid board **discoverable in the hub** and **refresh on realm-status hints** without expanding matchmaking, registry, or admission logic. Players open the board at an authored anchor with **F**; open boards coalesce refresh when `NotificationReconciliationService` reconciles live realm availability.

## Prerequisites

| Dependency | Status | Notes |
|---|---|---|
| TIN-59 Slice A list/queue UX | **Done** | `RaidBoardHubService`, `RaidBoardClient`, `RaidBoardHubState` |
| TIN-104 public-realm teleport | **Done** | Queue → admission → teleport path viable |
| TIN-105 live registry hub reads | **Done** | `ReconcileRealmStatus` reads `_LiveRealmRegistryHubSurface_QueryAPI` |
| TIN-58 party system | **Backlog** | Slice B keeps solo `raid_board:{userId}` queue semantics |

## Slice B boundary (in scope)

### TIN-57 — Map anchor + F-key interaction

- `RaidBoardConfig` — `BoardNamePrefix`, `DefaultBoardId`, `InteractionRangeStuds`, `OpenRequestAttribute`.
- Authored hub prop: `Workspace/Map/Stations/RaidBoard/Layout.model.json` with interaction anchor `RaidBoardHub_A` near Tinyfolk return approach.
- `InteractionResolver` — Tinyfolk-only candidate `raid_board_open` when within range of `RaidBoardHub_*` parts; sets `OpenRequestAttribute` on **F** (context interaction key).
- `RaidBoardClient` — listens for `OpenRequestAttribute`; toggles panel + forces list refresh (same behavior as debug open key). Debug `B` bind remains for Studio.

### TIN-125 — Realm-status notify fanout

- `NotificationReconciliationService.ReconcileRealmStatus` — after successful reconcile, best-effort call `_RaidBoardHubService_QueryAPI.BroadcastNotify` with bounded payload `{ reason, at }`.
- No MessagingService subscription changes; fanout uses existing `RaidBoardNotify` remote created by `RaidBoardHubService`.
- Test inject: `raidBoardHubApi` in `ConfigureForTests`.

## Out of scope / deferred

- Party-leader queue, invite gating, ready-check UI (TIN-58).
- Richer danger/reward presentation and treasury hooks (TIN-64).
- Owner permission settings UI (TIN-55).
- Server-side proximity validation on open (client F-key + existing list/queue role gates are sufficient for Slice B).
- Published-client teleport evidence (TIN-107).

## Data contracts

### Open request (client attribute, TIN-57)

| Field | Type | Notes |
|---|---|---|
| `RaidBoardOpenRequested` | boolean attribute | Set `true` by `InteractionResolver`; cleared by `RaidBoardClient` after handling |

### Notify hint (`RaidBoardNotify`, TIN-125)

```lua
-- Server → all clients (best-effort)
{
  reason = "realm_status_reconciled",
  at = number,
}
```

Client behavior unchanged: if panel visible, coalesced list refresh via `RaidBoardConfig.RefreshCoalesceSeconds`.

## Key files

| Area | Path |
|---|---|
| Config | `src/ReplicatedStorage/Shared/Config/RaidBoardConfig.luau` |
| Map anchor | `src/Workspace/Map/Stations/RaidBoard/Layout.model.json` |
| F-key | `src/StarterPlayer/StarterPlayerScripts/Client/InteractionResolver.client.luau` |
| Client panel | `src/StarterPlayer/StarterPlayerScripts/Client/RaidBoardClient.client.luau` |
| Notify seam | `src/ServerScriptService/Services/NotificationReconciliationService.luau` |
| Broadcast API | `src/ServerScriptService/Services/RaidBoardHubService.server.luau` (`BroadcastNotify`) |

## Acceptance criteria mapping (TIN-59)

| Criterion | Slice B plan |
|---|---|
| Tinyfolk can discover and open raid board in hub | Map anchor + F-key `raid_board_open` |
| Listings refresh safely on registry changes | `ReconcileRealmStatus` → `BroadcastNotify` + client coalesce |
| Slice A list/queue unchanged | No admission/registry edits |

## Validation

```powershell
.\scripts\run-validation.ps1 -ChangedOnly
lune run tests/notification_reconciliation_service.spec.luau
lune run tests/raid_board_hub_state.spec.luau
lune run tests/raid_board_hub_service_runtime_entrypoint.spec.luau
.\scripts\run-tests.ps1
```

## Risks

| Risk | Mitigation |
|---|---|
| Notify fanout spam on reconciliation loop | Client coalesce window; payload is hint-only (authoritative read still via list remote) |
| Attribute open races with debug key | Single consumer clears attribute; toggle logic shared |
| Map anchor placement blocks routes | Small footprint near `TinyfolkReturnPoint`; non-colliding platform parts |

## Follow-up (not Slice B)

- **TIN-58:** party-leader queue + migrate off `raid_board:` solo `partyId`.
- **TIN-64 / TIN-29:** trade conversion persistence bridge and treasury display.
