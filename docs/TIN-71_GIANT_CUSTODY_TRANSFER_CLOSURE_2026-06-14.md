# TIN-71 Giant-to-Giant Custody Transfer Closure (2026-06-14)

## Shipped

- Shared `CustodyTransferState` with request/confirm/cancel transitions, frozen terms snapshots, and capture-record term matching.
- `CustodyTransferConfig` for request expiry, confirm radius, cooldown, remotes, and readable transfer attributes.
- `CustodyTransferService` bilateral flow: outgoing Giant requests (confirms intent), incoming Giant confirms, settlement via `CaptureService.TransferTargetCustody`.
- Exact transfer terms projected to outgoing/incoming Giants and Tinyfolk target (anchor, custody window, absolute deadline, phase, remaining seconds, lawful end conditions).
- Tinyfolk notification via attributes + `CustodyTransferNotify` remote on request and settlement.
- Runtime event log hooks for request/settle/cancel when `_RuntimeEventLogService_QueryAPI` is available.
- Minimal `CustodyTransferClient` remote helpers for bounded gameplay UX.
- Specs: `tests/custody_transfer_state.spec.luau`, `tests/custody_transfer_service_runtime_entrypoint.spec.luau`.

## Deferred (in issue boundary notes)

- Structure occupant custodian reassignment hook (occupant keyed by target user id).
- F-key InteractionResolver wiring and presentation polish.
- Cross-server transfer execution.

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

All commands passed locally on 2026-06-14.
