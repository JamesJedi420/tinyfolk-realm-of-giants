# TIN-233 Ingress Rollout + Scheduler Hardening Kickoff (2026-05-30)

## Issue
- ID: TIN-233
- Title: Phase 2 additional ingress rollout and scheduler telemetry hardening
- Linear: https://linear.app/spectranoir/issue/TIN-233/phase-2-additional-ingress-rollout-and-scheduler-telemetry-hardening
- Status: In Progress

## Why This Slice Exists
- TIN-231 closed a bounded producer-ingress and diagnostics slice.
- Remaining deferred scope is broader ingress migration coverage and deeper scheduler telemetry hardening.
- This kickoff keeps the next phase bounded and test-driven.

## Proposed Bounded Scope
- Migrate the next batch of non-rescue admission ingress surfaces through shared producer/query seams.
- Harden scheduler telemetry around process-loop behavior with bounded counters/snapshots and deterministic query output.
- Extend runtime specs to cover each migrated ingress and telemetry behavior.

## Out of Scope
- Full observability dashboards.
- External telemetry platform integrations.
- Unbounded all-ingress conversion in one pass.

## Initial Implementation Plan
1. Enumerate remaining ingress surfaces not migrated in TIN-231.
2. Pick a small bounded migration batch and update those callers to shared producer/query seams.
3. Add bounded scheduler telemetry counters/snapshots for cadence and outcomes.
4. Extend focused runtime entrypoint specs for each migrated ingress.
5. Run `scripts/run-validation.ps1 -ChangedOnly` and targeted plus full suite checks.

## Progress Snapshot (2026-05-30)
- Completed batch 1:
	- `RescueContractService` rescue acceptance ingress now consumes `_RescueAdmissionService_QueryAPI.RequestRescueContractAdmission` as primary seam.
	- Concrete `RescueAdmissionService` query seam added in `src/ServerScriptService/Services/RescueAdmissionService.server.luau`.
	- Focused runtime coverage added:
		- `tests/rescue_contract_admission_ingress_runtime_entrypoint.spec.luau`
		- `tests/rescue_admission_service_runtime_entrypoint.spec.luau`
	- Default scripted suite wiring updated in `scripts/run-tests.ps1`.
- Validation evidence:
	- `scripts/run-validation.ps1 -ChangedOnly` pass
	- targeted rescue admission/ingress/runtime specs pass
	- full suite `scripts/run-tests.ps1` pass
- Commits:
	- `a6337c11` ingress caller migration + focused ingress spec
	- `253ac60f` concrete `RescueAdmissionService` seam + focused service spec

- Completed batch 2:
	- `RealmAdmissionQueueService` process-loop telemetry now records schedule/tick attempt-success-failure counters and last schedule/tick timestamps.
	- Loop diagnostics now emit bounded reason fields for schedule and tick failure paths.
	- Focused runtime coverage expanded in `tests/realm_admission_queue_service_runtime_entrypoint.spec.luau` for successful schedule/tick cadence and scheduler-throw failure snapshots.
- Validation evidence:
	- `scripts/run-validation.ps1 -ChangedOnly` pass
	- targeted queue runtime spec pass: `tests/realm_admission_queue_service_runtime_entrypoint.spec.luau`
	- full suite `scripts/run-tests.ps1` pass

## Next Bounded Step
- Enumerate the next non-rescue admission ingress surface and migrate one bounded caller batch through the shared query seam while preserving deterministic fallback compatibility.

## Exit Criteria
- Additional ingress surfaces migrated with deterministic failure-reason parity.
- Scheduler telemetry hardening seam implemented and test-backed.
- Boundary doc and closure checklist updated with in-scope/out-of-scope evidence.
