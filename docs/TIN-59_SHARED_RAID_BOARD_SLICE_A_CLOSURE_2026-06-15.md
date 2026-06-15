# TIN-59 Shared Raid Board — Slice A Closure

## Status

- Issue: [TIN-59](https://linear.app/spectranoir/issue/TIN-59/implement-shared-raid-board)
- Slice: A (client/hub presentation + queue)
- Implemented: 2026-06-15 (local validation clean; PR pending)

## Shipped

- `RaidBoardConfig` — remote names, cooldown/coalesce limits, reward-tier buckets, solo party prefix.
- `RaidBoardHubState` — deterministic public/available filter, sort, client-safe projection (no `privateServerId`/`jobId`).
- `RaidBoardHubPresentation` — panel/queue status formatting for client.
- `RaidBoardHubService` — list + queue remotes, Tinyfolk role gate, rate limits, owner display cache, admission enqueue via `_PartyMatchmakingAdmissionService_QueryAPI`, `_RaidBoardHubService_QueryAPI` diagnostics.
- `RaidBoardClient` — minimal ScreenGui (open with `B`, refresh, per-row queue, notify-driven coalesced refresh).

## Validation

```powershell
.\scripts\run-validation.ps1 -ChangedOnly
lune run tests/raid_board_hub_state.spec.luau
lune run tests/raid_board_hub_service_runtime_entrypoint.spec.luau
lune run tests/live_realm_hub_routing.spec.luau
lune run tests/party_matchmaking_admission_service_runtime_entrypoint.spec.luau
.\scripts\run-tests.ps1
```

All commands passed locally on 2026-06-15.

## Deferred (Slice B+)

- Hub map anchor / F-key interaction (TIN-57)
- Party-leader queue flow (TIN-58)
- Owner permission settings UI (TIN-55)
- Published-client teleport evidence (TIN-107)
- NotificationReconciliation → `RaidBoardNotify` wiring (TIN-125)

## Dependencies satisfied

- TIN-105 live registry hub reads
- TIN-104 durable reserved-server teleport routing
- TIN-117 admission queue path
