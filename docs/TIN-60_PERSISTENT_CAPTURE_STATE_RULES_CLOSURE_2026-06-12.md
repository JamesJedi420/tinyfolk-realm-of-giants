# TIN-60 Persistent Capture State Rules Closure (2026-06-12)

## Issue

- ID: TIN-60
- Title: Define persistent capture state rules
- Linear: https://linear.app/spectranoir/issue/TIN-60/define-persistent-capture-state-rules

## Shipped

- `CapturePersistenceRules` — deterministic session-runtime capture policy: storage owner (`session_runtime`), custody end reasons, prohibited permanent outcomes (`sold`, `deleted`, `account_lock`, `permanent`), max custody duration validation, timeout/logout resolution, reconnect/profile-hydration rejection, and escape-action availability.
- `CaptureService` — uses shared rules for timeout pruning, logout cleanup, post-accept record validation, and new `_CaptureService_QueryAPI` seams (`ValidateCustodyEndReason`, `ValidateCaptureRecord`, `CanTargetPerformEscapeAction`, `ResolveReconnectCaptureRestore`, `ResolveProfileCaptureHydration`, `GetCapturePersistenceRules`).
- `ContainmentRewardResolver` — custody end reason validation delegates to `CapturePersistenceRules`.
- Tests: `tests/capture_persistence_rules.spec.luau`; extended `tests/capture_service_runtime_entrypoint.spec.luau`.

## Acceptance mapping

| Criterion | Implementation |
|-----------|----------------|
| Captured Tinyfolk retain escape actions | `EscapeActions` + `CanTargetPerformEscapeAction` seam |
| Maximum duration or active escape path | `ValidateCaptureRecord` + `ResolveTimeout` + existing custody window |
| Capture does not survive logout | `ResolveLogout` + `PlayerRemoving` wiring |
| No delete/sell/account-lock | `ProhibitedEndReasons` + `ValidateCustodyEndReason` |
| Server-authoritative records | `ValidateCaptureRecord` on accept + session-only storage owner |

## Boundary

- No profile save/load pipeline for active capture runtime (deferred to future persistence slices).
- Grab/carry/containment reward math unchanged beyond shared end-reason source of truth.

## Validation

```powershell
.\scripts\run-validation.ps1 -ChangedOnly
lune run tests/capture_persistence_rules.spec.luau
lune run tests/capture_state.spec.luau
lune run tests/capture_service_runtime_entrypoint.spec.luau
lune run tests/containment_reward_resolver.spec.luau
.\scripts\run-tests.ps1
```
