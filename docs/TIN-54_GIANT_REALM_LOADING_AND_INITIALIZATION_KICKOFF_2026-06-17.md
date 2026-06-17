# TIN-54 Giant Realm Loading and Initialization - Kickoff

**Date:** 2026-06-17  
**Issue:** [TIN-54](https://linear.app/spectranoir/issue/TIN-54/implement-giant-realm-loading-and-initialization)  
**Milestone:** Persistence and Ownership  
**Related:** [TIN-49](https://linear.app/spectranoir/issue/TIN-49), [TIN-104](https://linear.app/spectranoir/issue/TIN-104)

## Goal

Load and initialize a Giant's personal realm from saved state with session-locked profile ownership, default starter creation, corrupt-data recovery, schema validation, and shutdown release.

## In scope

- Pure `GiantRealmLoadState` for save-root normalization (`loaded_existing`, `created_default`, `recovered_corrupt`).
- `ProfileStoreOwnerLayer` load recovery before schema validation; load outcome returned via gateway `meta`.
- `GiantRealmLoadService` orchestration with `_GiantRealmLoadService_QueryAPI` and RoleService delegation.
- Focused pure + runtime Lune specs; owner-layer recovery regression update.

## Out of scope

- Reserved-server allocation / teleport-entry wiring (TIN-104).
- Full build-mode gameplay expansion beyond existing apply snapshot seam.

## Acceptance mapping

| Criterion | Target |
|---|---|
| One persistent profile key per Giant realm | `GiantRealmLoadConfig.FormatProfileKey` |
| Load from saved data | `ResolveSaveRootForSession` + gateway load |
| Missing realm creates default starter | `created_default` outcome |
| Corrupt realm safe recovery | `recovered_corrupt` outcome |
| Loaded structures match schema | post-normalization `ValidateSaveRoot` |
| Session lock prevents dual mutation | existing owner-layer active session map |
| Profile releases on shutdown | RoleService cleanup via `SaveAndRelease` |
| Load errors logged | `GiantRealmLoadService` warn paths |

## Validation

```powershell
.\scripts\run-validation.ps1 -ChangedOnly
lune run tests/giant_realm_load_state.spec.luau
lune run tests/giant_realm_load_service_runtime_entrypoint.spec.luau
lune run tests/profile_store_owner_layer.spec.luau
```

## Deferred

- Dedicated BindToClose fanout in `GiantRealmLoadService.server` (RoleService still owns player-removing cleanup).
- Studio spot-check for first-time Giant realm bootstrap.
