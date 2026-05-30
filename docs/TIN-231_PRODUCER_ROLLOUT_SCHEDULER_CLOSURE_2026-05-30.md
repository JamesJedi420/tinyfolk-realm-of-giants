# TIN-231 Producer Rollout + Scheduler Refinement Closure (2026-05-30)

## Issue
- ID: TIN-231
- Title: Broaden AdmissionQueueProducer rollout and scheduler refinement
- Date Closed: 2026-05-30
- Owner: James Dye
- Branch/PR: master (local-only)

## Summary
- Closed the first bounded TIN-231 slice by extending non-rescue admission ingress coverage and validating deterministic producer payload/failure semantics.
- Added a second party-matchmaking ingress surface (`RequestPartyMatchAdmission`) routed through shared producer normalization.
- Migrated `ProfileTeleportHandoffService` admission enqueue to consume the party-matchmaking admission query seam instead of direct queue seam dependency.
- Added bounded queue-processing diagnostics (`GetProcessingDiagnostics`) on `RealmAdmissionQueueService` with cumulative counters and cloned last-outcome snapshot.

## Root Cause / Motivation
- TIN-230 closed the previous bounded producer rollout slice, but deferred broader ingress parity and operational scheduler/diagnostic hardening.
- Additional ingress migration was needed to keep failure-reason semantics deterministic across cross-server admission callers.
- Queue processing required a lightweight diagnostics seam for deterministic operational visibility without introducing broad telemetry platform coupling.

## Implementation
- `src/ServerScriptService/Services/PartyMatchmakingAdmissionService.server.luau`
  - Added `RequestPartyMatchAdmission` path via shared producer enqueue contract.
  - Reused shared request construction with deterministic operation-id prefixing and entry-type selection.
- `src/ServerScriptService/Services/ProfileTeleportHandoffService.luau`
  - Replaced direct queue query dependency with `_PartyMatchmakingAdmissionService_QueryAPI.RequestPartyMatchAdmission`.
  - Preserved retryable rejection behavior for unavailable/failed enqueue paths.
- `src/ServerScriptService/Services/RealmAdmissionQueueService.luau`
  - Added `GetProcessingDiagnostics` query surface with cumulative batch counters and cloned last outcome.
- Tests and suite wiring:
  - `tests/party_matchmaking_admission_service_runtime_entrypoint.spec.luau`
  - `tests/profile_teleport_handoff_service_runtime_entrypoint.spec.luau`
  - `tests/profile_teleport_handoff_admission_ingress_runtime_entrypoint.spec.luau`
  - `tests/realm_admission_queue_service_runtime_entrypoint.spec.luau`
  - `scripts/run-tests.ps1` explicit list includes the new focused ingress spec

## Validation Evidence
- Commit evidence:
  - `267c0cc6` `TIN-231: extend producer ingress and add admission diagnostics`
- Full suite evidence:
  - `./scripts/run-tests.ps1` -> full suite passed
- Changed-file validation evidence:
  - `./scripts/run-validation.ps1 -ChangedOnly` -> `stylua`, `selene`, and `luau-lsp` pass
- Focused runtime evidence (all pass):
  - `lune run tests/party_matchmaking_admission_service_runtime_entrypoint.spec.luau`
  - `lune run tests/profile_teleport_handoff_service_runtime_entrypoint.spec.luau`
  - `lune run tests/profile_teleport_handoff_admission_ingress_runtime_entrypoint.spec.luau`
  - `lune run tests/realm_admission_queue_service_runtime_entrypoint.spec.luau`

## Command Log Snapshot
- `lune run tests/party_matchmaking_admission_service_runtime_entrypoint.spec.luau` -> all checks passed
- `lune run tests/profile_teleport_handoff_service_runtime_entrypoint.spec.luau` -> all checks passed
- `lune run tests/profile_teleport_handoff_admission_ingress_runtime_entrypoint.spec.luau` -> all checks passed
- `lune run tests/realm_admission_queue_service_runtime_entrypoint.spec.luau` -> all checks passed
- `./scripts/run-tests.ps1` -> full suite passed
- `./scripts/run-validation.ps1 -ChangedOnly` -> stylua/selene/luau-lsp pass

## Pre-Closure Checklist

### 1. Implementation Gaps
- Checked: yes.
- Notes: additional non-rescue ingress path, handoff ingress migration, and diagnostics seam were implemented in this bounded slice.
- Remaining gap follow-up: migrate broader ingress surfaces and continue scheduler telemetry hardening in a separate bounded phase.

### 2. Validation and Evidence Strength
- Checked: yes.
- Direct criteria coverage:
  - producer ingress parity -> `tests/party_matchmaking_admission_service_runtime_entrypoint.spec.luau`
  - handoff ingress seam migration -> `tests/profile_teleport_handoff_service_runtime_entrypoint.spec.luau`
  - focused new ingress contract -> `tests/profile_teleport_handoff_admission_ingress_runtime_entrypoint.spec.luau`
  - diagnostics seam behavior -> `tests/realm_admission_queue_service_runtime_entrypoint.spec.luau`
  - full regression confidence -> `scripts/run-tests.ps1`
  - changed-file gate -> `scripts/run-validation.ps1 -ChangedOnly`
- Residual testing risk: low for bounded TIN-231 scope.

### 3. Required Document Updates
- Checked: yes.
- Updated docs:
  - `docs/TIN-231_PRODUCER_ROLLOUT_SCHEDULER_CLOSURE_2026-05-30.md` (this record)
  - `docs/SYSTEM_BOUNDARIES.md` status wording updated from TIN-231 kickoff to delivered closure evidence

### 4. Related Issue Boundary and Dependencies
- Checked: yes.
- Included in this closure:
  - additional non-rescue producer ingress path (`RequestPartyMatchAdmission`)
  - `ProfileTeleportHandoffService` ingress migration to party-matchmaking seam
  - bounded queue-processing diagnostics query seam
- Explicitly out of scope:
  - remaining ingress migrations beyond current bounded paths
  - expanded scheduler telemetry hardening and richer observability surfaces
  - dashboard/platform telemetry integration
- Dependency notes:
  - TIN-117 queue runtime/store/processor path remains foundational dependency
  - TIN-229 resolver seam remains prerequisite context
  - TIN-230 closure established previous producer rollout baseline

### 5. Remaining Cleanup
- Checked: yes.
- Dead code or TODOs introduced: none identified in closure prep.
- Deferred items filed: follow-up issue for broader ingress rollout + scheduler telemetry hardening phase 2.

## Risk Assessment
- Functional risk: low.
- Regression risk: low.
- Why: focused ingress/diagnostics runtime coverage is green, full suite is green, and changed-file validation passes.

## Final Decision
- Ready for Done: yes.
- Recommended Linear state: Done.
- Basis: implementation, validation evidence, document updates, boundary checks, and cleanup checks are complete for bounded TIN-231 scope.
