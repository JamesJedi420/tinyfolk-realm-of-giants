# TIN-74 Logout and Disconnect Resolution Kickoff (2026-06-13)

## Issue

- ID: TIN-74
- Title: Implement logout and disconnect resolution
- Milestone: Capture, Rescue, and Routing
- Linear: https://linear.app/spectranoir/issue/TIN-74/implement-logout-and-disconnect-resolution

## Goal

Handle players leaving during capture safely: return-pending for disconnected Tinyfolk, visitor release when Giants leave, and safe valid reconnect spawn without item duplication.

## Scope

- Add shared `DisconnectResolutionState` for logout/reconnect resolution plans.
- Extend `SafeLocationProfileState` with `logout` return reason and clear helper.
- Wire `CaptureService` logout handling for return-pending persistence and online target safe-return when custodian disconnects.
- Wire `RoleService` reconnect spawn to prefer persisted safe-location return points.
- Add `DisconnectSafeReturnCaller` for profile persist + escape safe-return seams.

## Boundary

- No full raid/trade/ransom disconnect matrix (capture-focused slice).
- No cross-server teleport orchestration changes beyond existing pending-recovery flow.
- Profile autosave/crash durability relies on existing `ProfilePersistenceLifecycle` save-on-removing.

## Validation

```powershell
.\scripts\run-validation.ps1 -ChangedOnly
lune run tests/disconnect_resolution_state.spec.luau
lune run tests/safe_location_profile_state.spec.luau
lune run tests/capture_service_runtime_entrypoint.spec.luau
lune run tests/role_service_runtime_entrypoint.spec.luau
.\scripts\run-tests.ps1
```
