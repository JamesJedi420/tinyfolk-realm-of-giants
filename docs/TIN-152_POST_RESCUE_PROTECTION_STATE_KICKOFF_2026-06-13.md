# TIN-152 Post-Rescue Protection State Kickoff (2026-06-13)

## Issue

- ID: TIN-152
- Title: Implement post-rescue protection state
- Milestone: Capture, Rescue, and Routing
- Linear: https://linear.app/spectranoir/issue/TIN-152/implement-post-rescue-protection-state

## Goal

Formalize short-lived defensive post-rescue protection with bounded effects and early cancellation on protection-breaking actions.

## Scope

- Add shared `PostRescueProtectionState` for protection evaluation, breaking actions, and effect multipliers.
- Extend `RescueContractService` grant/clear with movement boost and query seams (`IsTargetPostRescueProtected`, `CancelPostRescueProtection`).
- Enforce no-grab via `GrabService`; keep capture rejection via `CaptureService`.
- Reduce escape request cooldown while protected via `EscapeService`.
- Cancel protection on contextual-task completion via `PostRescueProtectionCancellationCaller`.

## Boundary

- Defensive short-lived state only; no safe-zone immunity or profile persistence.
- No new rescue contract queue or capture rule semantics.

## Validation

```powershell
.\scripts\run-validation.ps1 -ChangedOnly
lune run tests/post_rescue_protection_state.spec.luau
lune run tests/rescue_contract_service_runtime_entrypoint.spec.luau
lune run tests/grab_service_runtime_entrypoint.spec.luau
lune run tests/capture_service_runtime_entrypoint.spec.luau
lune run tests/escape_service_runtime_entrypoint.spec.luau
lune run tests/construction_service_runtime_entrypoint.spec.luau
.\scripts\run-tests.ps1
```
