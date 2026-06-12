# TIN-60 Persistent Capture State Rules Kickoff (2026-06-12)

## Issue

- ID: TIN-60
- Title: Define persistent capture state rules
- Milestone: Capture, Rescue, and Routing
- Linear: https://linear.app/spectranoir/issue/TIN-60/define-persistent-capture-state-rules

## Goal

Define bounded capture persistence rules: temporary/interactive/escapable custody, server-authoritative records, and logout/timeout behavior without a full profile persistence slice.

## Scope

- Add pure `CapturePersistenceRules` in `Shared/GiantRealm/` for storage ownership, custody end reasons, timeout/logout/reconnect/profile-hydration policy, escape-action availability, and capture record validation.
- Wire `CaptureService` and `ContainmentRewardResolver` to the shared rules module.
- Expose `_CaptureService_QueryAPI` validation seams for custody end reasons, record validation, escape actions, reconnect restore, and profile hydration rejection.
- Add focused specs; keep existing grab/carry/containment reward flows unchanged.

## Boundary

- Rule definition + server validation seams only.
- No profile save/load pipeline for active capture runtime.
- No changes to grab/carry physics or escape outcome authority.

## Validation

```powershell
.\scripts\run-validation.ps1 -ChangedOnly
lune run tests/capture_persistence_rules.spec.luau
lune run tests/capture_state.spec.luau
lune run tests/capture_service_runtime_entrypoint.spec.luau
lune run tests/containment_reward_resolver.spec.luau
.\scripts\run-tests.ps1
```
