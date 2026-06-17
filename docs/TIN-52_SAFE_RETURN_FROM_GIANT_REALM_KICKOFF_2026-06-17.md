# TIN-52 Safe Return from Giant Realm - Kickoff

**Date:** 2026-06-17  
**Issue:** [TIN-52](https://linear.app/spectranoir/issue/TIN-52/implement-safe-return-from-giant-realm)  
**Milestone:** Capture, Rescue, and Routing  
**Related:** [TIN-50](https://linear.app/spectranoir/issue/TIN-50), [TIN-74](https://linear.app/spectranoir/issue/TIN-74)

## Goal

Ensure Tinyfolk cannot be permanently trapped in a Giant realm by defining return triggers, pending-return resolution, and safe fallback orchestration across logout, shutdown, timeout, escape, giant disconnect, and moderation fallback paths.

## In scope

- Pure `RealmSafeReturnState` return/join plan classification on top of `PlayerLocationState`.
- `RealmSafeReturnService` orchestration: location transitions, assignment abort, handoff invalidation, profile safe-location persistence, captivity safe-return seam.
- Lifecycle hooks: player logout, server shutdown (`BindToClose`), join pending-return resolution, giant disconnect visitor return.
- Focused pure + runtime Lune specs.

## Out of scope

- Published-client multi-server teleport spot-check.
- Full moderation enforcement UX beyond return fallback seam.
- Replacing capture-specific logout handling in `CaptureService` (coexists; guest/invader logout centralized here).

## Acceptance mapping

| Criterion | Target |
|---|---|
| Defined return path for all triggers | `RealmSafeReturnState.ResolveReturnPlan` |
| Logout from realm creates pending return | logout trigger + `ResolveDisconnect` + profile persist |
| Server shutdown returns on next join | shutdown persist + join resolution |
| Captured state bounded | timeout/moderation captivity safe-return seam |
| Testable logic | pure + runtime specs |

## Validation

```powershell
.\scripts\run-validation.ps1 -ChangedOnly
lune run tests/realm_safe_return_state.spec.luau
lune run tests/realm_safe_return_service_runtime_entrypoint.spec.luau
```

## Deferred

- Wire `CaptureService` logout to delegate entirely to `RealmSafeReturnService`.
- Studio evidence for shutdown/reconnect return spawn.
