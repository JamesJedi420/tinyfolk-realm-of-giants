# TIN-66 Tinyfolk Trophy Display Opt-Out — Kickoff

**Date:** 2026-06-09  
**Issue:** [TIN-66](https://linear.app/spectranoir/issue/TIN-66/implement-giant-trophy-and-reputation-system)

## Slice boundary

- `TrophyDisplayPolicyState` — player-profile preference read/write (`trophyDisplayPreference.optOutOfNameDisplay`).
- `TrophyDisplayPolicyService` — server-owned preference persistence, query API, and Tinyfolk-only remote update seam.
- `TrophyState.ComputeTargetDisplayToken` — opt-out maps to `Private Visitor`; default keeps visitor reference token (`ref-{hash}`).
- `TrophyService` — resolves target opt-out at record time via `_TrophyDisplayPolicyService_QueryAPI`.
- `TrophyDisplayPolicyClient` — Tinyfolk HUD toggle (`O` key + button) for trophy display privacy.
- Player attribute projection: `TinyfolkTrophyNameOptOut`.

## Deferred

- Cross-realm opt-out sync (prototype uses in-session profile lookup; unknown/offline targets default to opt-out-safe anonymous token).
- Raw Roblox display-name trophy labels (prototype remains display-safe tokens only).

## Validation

```powershell
lune run tests/trophy_display_policy_state.spec.luau
lune run tests/trophy_display_policy_service_runtime_entrypoint.spec.luau
lune run tests/trophy_state.spec.luau
lune run tests/trophy_service_runtime_entrypoint.spec.luau
lune run tests/event_state_ownership_model.spec.luau
.\scripts\run-validation.ps1 -ChangedOnly
```
