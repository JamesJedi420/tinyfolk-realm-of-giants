# TIN-52 Safe Return from Giant Realm - Closure

**Date:** 2026-06-17  
**Issue:** [TIN-52](https://linear.app/spectranoir/issue/TIN-52/implement-safe-return-from-giant-realm)  
**Milestone:** Capture, Rescue, and Routing  
**Status:** Closed slice

## Shipped

- **Return plan classification:** `RealmSafeReturnState` maps escape, timeout, logout, server shutdown, giant disconnect, and moderation fallback triggers to location/assignment/handoff/persistence plans on top of `PlayerLocationState`.
- **Orchestration service:** `RealmSafeReturnService` applies return plans, persists safe-location profile snapshots, delegates captivity relocation to `CaptivitySafeReturnCaller`, and exposes `_RealmSafeReturnService_QueryAPI`.
- **Lifecycle hooks:** `RealmSafeReturnService.server.luau` wires player logout, server shutdown (`BindToClose`), join pending-return resolution, and giant-disconnect visitor return.

## Validation

```powershell
.\scripts\run-validation.ps1 -ChangedOnly
lune run tests/realm_safe_return_state.spec.luau
lune run tests/realm_safe_return_service_runtime_entrypoint.spec.luau
```

Local rerun on 2026-06-17: all commands passed.

## Acceptance mapping

| Criterion | Status | Implementation |
|---|---|---|
| Defined return path for all triggers | PASS | `RealmSafeReturnState.ResolveReturnPlan` |
| Logout from realm creates pending return | PASS | logout trigger + `ResolveDisconnect` + profile persist |
| Server shutdown returns on next join | PASS | shutdown persist + `ResolvePendingReturnOnJoin` |
| Captured state bounded | PASS | timeout/moderation captivity safe-return seam |
| Return logic testable | PASS | pure + runtime Lune specs |

## Deferred

- Delegate capture-specific logout entirely from `CaptureService` to `RealmSafeReturnService`.
- Published-client shutdown/reconnect spot-check.
