# TIN-57 Shared Tinyfolk Spawn Hub — Kickoff

**Date:** 2026-06-16  
**Issue:** [TIN-57](https://linear.app/spectranoir/issue/TIN-57/implement-shared-tinyfolk-spawn-hub)  
**Milestone:** Admission and Queueing  
**Related:** [TIN-58](https://linear.app/spectranoir/issue/TIN-58) (party system), [TIN-59](https://linear.app/spectranoir/issue/TIN-59) (raid board), [TIN-49](https://linear.app/spectranoir/issue/TIN-49) (persistent realm architecture)

## Goal

Deliver a **safe shared Tinyfolk spawn hub** independent of any Giant realm. Hub supports realm activity routing (raid board, party, portal anchors) with **no Giant capture** in the hub.

## In scope

- `TinyfolkHubConfig` + `TinyfolkHubState` — spawn name resolution, shared-hub safe-zone policy, activity eligibility.
- `TinyfolkHubService` — projects `LocationCategory`, `InTinyfolkHub`, and `SharedHub` safe-zone attrs; ensures `shared_hub` assignment on Tinyfolk role lock.
- `RoleService` — Tinyfolk spawn at `TinyfolkHubSpawn` with legacy `TinyfolkSpawn` fallback.
- Map anchors in `Workspace/Map/TinyfolkWorld` + `TinyfolkHubSpawn` in `Map/Spawns`.
- Party hub F-key via `PartyHub_*` anchor (`TinyfolkPartyConfig.OpenRequestAttribute`).
- Raid board + party handlers gate on hub activity eligibility when hub service is present.

## Out of scope / deferred

- Full district growth (TIN-14).
- Shops, contracts, rumors surfaces.
- Persisting owner access mode / invite lists across sessions.
- `friends_only` offline friends graph (online `IsFriendsWith` only when enforced elsewhere).

## Validation

```powershell
.\scripts\run-validation.ps1 -ChangedOnly
lune run tests/tinyfolk_hub_state.spec.luau
lune run tests/tinyfolk_hub_service_runtime_entrypoint.spec.luau
lune run tests/role_service_runtime_entrypoint.spec.luau
lune run tests/raid_board_hub_service_runtime_entrypoint.spec.luau
lune run tests/tinyfolk_party_service_runtime_entrypoint.spec.luau
.\scripts\run-tests.ps1
```
