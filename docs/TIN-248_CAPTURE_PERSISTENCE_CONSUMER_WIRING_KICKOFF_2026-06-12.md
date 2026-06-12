# TIN-248 Capture Persistence Consumer Wiring Kickoff (2026-06-12)

## Issue

- ID: TIN-248
- Title: Wire capture persistence rules to escape/grab/rescue consumers
- Milestone: Capture, Rescue, and Routing
- Linear: https://linear.app/spectranoir/issue/TIN-248/wire-capture-persistence-rules-to-escapegrabrescue-consumers

## Goal

Wire TIN-60 capture persistence escape-action seams into escape, grab counterplay, and rescue contract consumer services.

## Scope

- Call `_CaptureService_QueryAPI.CanTargetPerformEscapeAction` from bounded paths in `EscapeService` (route escape + transport boarding), `GrabService` (counterplay), and `RescueContractService` (request + complete).
- Use `CapturePersistenceRules.EscapeActions` action ids consistently.
- Add focused runtime entrypoint coverage for blocked actions and capture query faults.

## Boundary

- Consumer wiring only — no changes to `CapturePersistenceRules` semantics or profile persistence.
- Fail-open when capture query API is unavailable; fail-closed on query fault.

## Validation

```powershell
.\scripts\run-validation.ps1 -ChangedOnly
lune run tests/escape_service_runtime_entrypoint.spec.luau
lune run tests/grab_service_runtime_entrypoint.spec.luau
lune run tests/rescue_contract_service_runtime_entrypoint.spec.luau
.\scripts\run-tests.ps1
```
