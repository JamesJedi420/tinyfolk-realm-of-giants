# TIN-70 Ransom Board Kickoff (2026-06-15)

## Issue

- ID: TIN-70
- Title: Implement ransom board
- Milestone: Capture, Rescue, and Routing
- Linear: https://linear.app/spectranoir/issue/TIN-70/implement-ransom-board

## Goal

Turn capture into a bounded in-platform negotiation loop: Giants post frozen ransom terms for captured Tinyfolk, allies pay stored Food or satisfy the escape objective threshold to release them, while captivity deadlines and escape paths remain intact.

## Scope

- Add shared `RansomBoardState` for offer post/settle/cancel transitions and immutable terms snapshots.
- Add `RansomBoardConfig` tuning and readable attribute names.
- Add `RansomBoardService` post/settle/cancel query API, stored-food spend, custody release via `CaptureService`, and runtime event-log hooks.
- Add minimal `RansomBoardClient` remote helpers and notify projection for exact terms before settlement.

## Boundary

- Server-authoritative ransom terms/settlement only; no off-platform payment or moderation UI (TIN-139).
- Payment release spends realm stored Food; objective release requires `IsEscapeObjectiveThresholdMet`.
- No authored board anchor polish or full HUD presentation in this slice.
- Escape/struggle/timeout paths remain unchanged and independent of ransom offers.

## Validation

```powershell
.\scripts\run-validation.ps1 -ChangedOnly
lune run tests/ransom_board_state.spec.luau
lune run tests/ransom_board_service_runtime_entrypoint.spec.luau
.\scripts\run-tests.ps1
```
