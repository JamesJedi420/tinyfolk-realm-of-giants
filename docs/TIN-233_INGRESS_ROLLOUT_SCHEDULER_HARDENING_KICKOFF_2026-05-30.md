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

- Completed batch 3:
	- Concrete `ProfileTeleportAdmissionService` query seam added in `src/ServerScriptService/Services/ProfileTeleportAdmissionService.server.luau`.
	- `ProfileTeleportHandoffService` admission ingress now consumes `_ProfileTeleportAdmissionService_QueryAPI.RequestTeleportHandoffAdmission` as primary seam.
	- Deterministic compatibility fallback retained to `_PartyMatchmakingAdmissionService_QueryAPI.RequestPartyMatchAdmission` only when the new primary seam is unavailable.
	- Focused runtime coverage added/expanded:
		- `tests/profile_teleport_admission_service_runtime_entrypoint.spec.luau`
		- `tests/profile_teleport_handoff_admission_ingress_runtime_entrypoint.spec.luau`
		- `tests/profile_teleport_handoff_service_runtime_entrypoint.spec.luau`
	- Default scripted suite wiring updated in `scripts/run-tests.ps1`.
- Validation evidence:
	- `scripts/run-validation.ps1 -ChangedOnly` pass
	- targeted teleport admission/handoff ingress/runtime specs pass
	- full suite `scripts/run-tests.ps1` pass

- Completed batch 4:
	- `ProfileTeleportHandoffService` now emits bounded ingress path diagnostics for admission routing:
		- primary path attempts/success/failure
		- fallback path attempts/success/failure
		- last path, last reason, and last primary/fallback reason snapshots
	- Focused runtime coverage expanded to assert deterministic diagnostics for:
		- primary seam success
		- fallback seam success
		- primary+fallback unavailable failure
		- primary exception failure without fallback
	- No request/response contract drift introduced for existing handoff callers.
- Validation evidence:
	- `scripts/run-validation.ps1 -ChangedOnly` pass
	- targeted teleport handoff ingress/runtime diagnostics specs pass
	- full suite `scripts/run-tests.ps1` pass

- Completed batch 5:
	- `PartyMatchmakingAdmissionService` now emits bounded resolver/enqueue diagnostics snapshots through `_PartyMatchmakingAdmissionService_QueryAPI.GetAdmissionDiagnostics`.
	- Resolver diagnostics now capture attempts, success/failure, direct-target fallback usage, and last resolver path/reason snapshots.
	- Enqueue diagnostics now capture attempts, success/failure, and last enqueue outcome reason snapshots.
	- Focused runtime coverage expanded in `tests/party_matchmaking_admission_service_runtime_entrypoint.spec.luau` to assert deterministic diagnostics across accepted, resolver-unavailable/rejected, and enqueue failure paths.
- Validation evidence:
	- `scripts/run-validation.ps1 -ChangedOnly` pass
	- targeted party admission runtime diagnostics spec pass
	- full suite `scripts/run-tests.ps1` pass

## Next Bounded Step
- Extend ingress observability parity to rescue admission caller seams by asserting cross-service diagnostics consistency between `RescueContractService` ingress diagnostics and `RescueAdmissionService` enqueue outcomes in focused runtime specs.

## Exit Criteria
- Additional ingress surfaces migrated with deterministic failure-reason parity.
- Scheduler telemetry hardening seam implemented and test-backed.
- Boundary doc and closure checklist updated with in-scope/out-of-scope evidence.
