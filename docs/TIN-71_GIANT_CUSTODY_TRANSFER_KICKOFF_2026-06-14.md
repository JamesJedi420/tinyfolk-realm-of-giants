# TIN-71 Giant-to-Giant Custody Transfer Kickoff (2026-06-14)

## Issue

- ID: TIN-71
- Title: Implement Giant-to-Giant custody transfer
- Milestone: Capture, Rescue, and Routing
- Linear: https://linear.app/spectranoir/issue/TIN-71/implement-giant-to-giant-custody-transfer

## Goal

Ship bounded server-authoritative Giant-to-Giant custody transfer with bilateral confirmation, frozen transfer terms, and Tinyfolk notification while preserving captivity anchors and escape/rescue/timeout paths.

## Scope

- Add shared `CustodyTransferState` for pending request/confirm/cancel transitions and immutable terms snapshots.
- Add `CustodyTransferService` request/confirm/cancel query API and minimal remotes.
- Reuse `CaptureService.TransferTargetCustody` + `CaptivityDurationState.ResolveTransfer` on settlement.
- Project exact transfer terms (anchor, custody window, absolute deadline, phase, end conditions) to Giants and Tinyfolk via attributes + notify remote.
- Log transfer request/settle/cancel events through runtime event log seam when available.

## Boundary

- No ransom board (TIN-70), moderation UI (TIN-75/TIN-139), or cross-server transfer execution.
- No structure occupant reassignment hook (occupant keyed by target user id).
- Client F-key interaction polish deferred; minimal `CustodyTransferClient` remote helpers only.

## Validation

```powershell
.\scripts\run-validation.ps1 -ChangedOnly
lune run tests/custody_transfer_state.spec.luau
lune run tests/custody_transfer_service_runtime_entrypoint.spec.luau
lune run tests/captivity_duration_state.spec.luau
lune run tests/capture_service_runtime_entrypoint.spec.luau
lune run tests/capture_state.spec.luau
.\scripts\run-tests.ps1
```
