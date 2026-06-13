# TIN-74 Logout and Disconnect Resolution Closure (2026-06-13)

## Issue

- ID: TIN-74
- Title: Implement logout and disconnect resolution
- Linear: https://linear.app/spectranoir/issue/TIN-74/implement-logout-and-disconnect-resolution

## Shipped

- `DisconnectResolutionState` — pure logout/reconnect resolution plans (return-pending, custodian visitor release, session-runtime clear).
- `DisconnectSafeReturnCaller` — profile return-pending persist and online captivity safe-return via escape query seam.
- `SafeLocationProfileState` — `logout` return reason and `ClearSafeLocation` consume helper.
- `CaptureService` — on disconnect: persist return-pending for captured Tinyfolk; safe-return online targets when custodian Giant leaves.
- `RoleService` — reconnect spawn prefers persisted safe-location return point and clears consumed snapshot.

## Acceptance mapping

| Criterion | Status |
|-----------|--------|
| Tinyfolk disconnect during capture resolves safely | PASS — logout return-pending persisted to profile |
| Giant disconnect does not trap visitors | PASS — online targets receive captivity safe-return |
| Server crash does not lose profile state unexpectedly | PASS (bounded) — relies on existing save-on-removing lifecycle |
| Reconnect places player in safe valid location | PASS — RoleService spawns at `TinyfolkReturnPoint` from profile |
| Disconnect cannot be exploited for item duplication | PASS (bounded) — capture session runtime not restored; safe-location consumed on spawn |

## Deferred

- Raid/trade/ransom disconnect matrix beyond capture custody.
- Studio spot-check for reconnect spawn placement.

## Validation

```powershell
.\scripts\run-validation.ps1 -ChangedOnly
lune run tests/disconnect_resolution_state.spec.luau
lune run tests/safe_location_profile_state.spec.luau
lune run tests/capture_service_runtime_entrypoint.spec.luau
lune run tests/role_service_runtime_entrypoint.spec.luau
.\scripts\run-tests.ps1
```
