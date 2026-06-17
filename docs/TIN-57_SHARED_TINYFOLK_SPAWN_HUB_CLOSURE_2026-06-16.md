# TIN-57 Shared Tinyfolk Spawn Hub — Closure

**Date:** 2026-06-16  
**Issue:** [TIN-57](https://linear.app/spectranoir/issue/TIN-57/implement-shared-tinyfolk-spawn-hub)  
**PR:** _(filled at merge)_

## Shipped

- `TinyfolkHubConfig`, `TinyfolkHubState`, `TinyfolkHubService` — shared-hub spawn routing, `SharedHub` safe-zone projection, `shared_hub` assignment on Tinyfolk role lock, activity eligibility query API.
- `RoleService` — Tinyfolk spawn at `TinyfolkHubSpawn` with legacy `TinyfolkSpawn` fallback.
- Hub map anchors: `TinyfolkHubSpawn`, `SharedHubSafeZone_A`, `PartyHub_A`, `RealmPortalHub_A`, hub platform near `TinyfolkReturnPoint`.
- Party hub F-key (`party_hub_open`) + `TinyfolkPartyOpenRequested` attribute consumer.
- Raid board + party server handlers gate on hub activity eligibility when hub service is present.

## Validation

- `.\scripts\run-validation.ps1 -ChangedOnly`
- `lune run tests/tinyfolk_hub_state.spec.luau`
- `lune run tests/tinyfolk_hub_service_runtime_entrypoint.spec.luau`
- `lune run tests/role_service_runtime_entrypoint.spec.luau`
- `lune run tests/raid_board_hub_service_runtime_entrypoint.spec.luau`
- `lune run tests/tinyfolk_party_service_runtime_entrypoint.spec.luau`
- `.\scripts\run-tests.ps1`

## Deferred

- Full district growth (TIN-14), shops/contracts/rumors surfaces.
- Persisting owner access mode / invite lists across sessions.
- Offline friends graph for `friends_only`.
