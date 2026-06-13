# TIN-85 Tinyfolk Struggle and Escape Minigame Kickoff (2026-06-13)

## Issue

- ID: TIN-85
- Title: Implement Tinyfolk struggle and escape minigame
- Milestone: Capture, Rescue, and Routing
- Linear: https://linear.app/spectranoir/issue/TIN-85/implement-tinyfolk-struggle-and-escape-minigame

## Goal

Prevent capture from becoming an instant loss by giving captured Tinyfolk active struggle progress and ally rescue acceleration, while allowing Giants to suppress escape by reaching valid containment.

## Scope

- Add shared `CaptivityEscapeProgressState` for struggle progress, decay, suppression, and completion.
- Extend `CaptureConfig` with struggle/assist/decay tuning and readable player attributes.
- Add `CaptivityEscapeService` for server-authoritative struggle, ally assist, and containment suppression.
- Wire struggle completion to `CaptureService.ResolveCustodyEnd(..., "released")`.
- Wire containment suppression to `CaptureService.PromoteTargetToContained` plus progress reset.
- Add minimal client remotes for captured struggle (`F`) and ally assist (`R`).

## Boundary

- No raid/trade/ransom disconnect paths (deferred from TIN-74).
- No Studio spot-check for reconnect spawn placement.
- No HUD/VFX/audio polish beyond attribute projection.
- No profile persistence of in-progress escape meters.

## Validation

```powershell
.\scripts\run-validation.ps1 -ChangedOnly
lune run tests/captivity_escape_progress_state.spec.luau
lune run tests/captivity_escape_service_runtime_entrypoint.spec.luau
lune run tests/capture_persistence_rules.spec.luau
lune run tests/capture_service_runtime_entrypoint.spec.luau
lune run tests/rescue_contract_service_runtime_entrypoint.spec.luau
.\scripts\run-tests.ps1
```
