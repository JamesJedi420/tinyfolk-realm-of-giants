# TIN-223 Giant Staged Threat Progression Closure (2026-05-22)

## Issue
- ID: TIN-223
- Title: Implement Giant staged threat progression
- Date Closed: 2026-05-22
- Owner: [fill]
- Branch/PR: master (local-only)

## Summary
- Confirmed and validated bounded Giant staged threat progression in the Tinyfolk status pipeline.
- Shared deterministic stage logic maps coarse warning levels to coarse threat stages and decays by one step on hold windows.
- Runtime status service resolves and projects raid threat stage as an attribute-visible, readability-safe signal.
- Scope remains bounded to pressure progression visibility and state transitions; no exact tracking, no automatic capture behavior, and no unbeatable late-game mechanic were added.

## Root Cause / Motivation
- TIN-223 required a bounded pressure-progression layer to make late-raid threat escalation legible without introducing hard-lock outcomes.
- Existing warning-only cues needed deterministic stage memory/decay behavior over time.

## Implementation
- `src/ReplicatedStorage/Shared/TinyfolkStatus/GiantThreatStageLogic.luau`
  - Deterministic stage state machine with coarse stages (`calm`, `watch`, `pressure`, `critical`).
  - Warning-to-stage mapping and one-step decay after configured hold duration.
- `src/ReplicatedStorage/Shared/Config/TinyfolkStatusConfig.luau`
  - `GiantThreatStage` config block for levels, warning-level mapping, and decay seconds.
- `src/ServerScriptService/Services/TinyfolkStatusService.server.luau`
  - Runtime integration via `GiantThreatStageLogic.ResolveTick`.
  - Projects stage to `TinyfolkRaidHudThreatStage` and query API snapshot seam.
- `tests/giant_threat_stage_logic.spec.luau`
  - Covers default stage, promotion, hold-before-decay, and one-step decay progression to calm.
- `tests/tinyfolk_status_service_runtime_entrypoint.spec.luau`
  - Covers runtime stage projection and decay behavior in service flow.

## Validation Evidence
- Fresh full listed suite run before closure prep:
  - `./scripts/run-tests.ps1`
  - Output captured at `test_output_tin223_preclosure.txt`
  - Key pass markers include:
    - `capture_service_runtime_entrypoint: all checks passed`
    - `score_service_runtime_entrypoint: all checks passed`
    - `realm_objective_service_runtime_entrypoint: all checks passed`
    - `timed_condition_states_runtime_entrypoint: all checks passed`
    - `headless_match_simulation: all checks passed`
    - `23 passed, 0 failed` (capture-state block)
- Explicit TIN-223 targeted confirmation appended to same evidence log:
  - `lune run tests/giant_threat_stage_logic.spec.luau`
  - `lune run tests/tinyfolk_status_service_runtime_entrypoint.spec.luau`
  - Key pass markers include:
    - `PASS [calm stage is default]`
    - `PASS [raid threat stage reflects nearby giant pressure]`
    - `PASS [raid threat stage decays one step at a time]`

## Command Log Snapshot
- `./scripts/run-tests.ps1` -> listed suite pass markers recorded in `test_output_tin223_preclosure.txt`
- `lune run tests/giant_threat_stage_logic.spec.luau` -> stage progression checks passed
- `lune run tests/tinyfolk_status_service_runtime_entrypoint.spec.luau` -> runtime threat-stage projection and decay checks passed

## Commits
- `10438969` `Add snare traps and giant threat stages`

## Pre-Closure Checklist

### 1. Implementation Gaps
- Checked: yes.
- Notes: bounded staged-threat progression behavior (promotion, hold, one-step decay) is implemented in shared logic and runtime integration.
- Remaining gap follow-up: none identified in this bounded slice.

### 2. Validation and Evidence Strength
- Checked: yes.
- Direct criteria coverage:
  - shared stage progression behavior -> `tests/giant_threat_stage_logic.spec.luau`
  - runtime projection/decay behavior -> `tests/tinyfolk_status_service_runtime_entrypoint.spec.luau`
  - cross-slice regression gate -> `scripts/run-tests.ps1` fresh run with captured pass markers.
- Residual testing risk: low.

### 3. Required Document Updates
- Checked: yes.
- Updated docs:
  - `docs/TIN-223_GIANT_THREAT_STAGE_CLOSURE_2026-05-22.md` (this record)
  - pointer added in `docs/SYSTEM_BOUNDARIES.md`

### 4. Related Issue Boundary and Dependencies
- Checked: yes.
- Included in this closure:
  - coarse staged threat progression logic and status-service projection seam
- Explicitly out of scope:
  - exact Giant tracking/location disclosure
  - automatic capture/custody outcomes
  - invulnerable or unavoidable late-game states
- Dependency notes:
  - uses existing Tinyfolk status warning signal as input (`warningLevel -> stage`).

### 5. Remaining Cleanup
- Checked: yes.
- Dead code or TODOs introduced: none in this closure prep.
- Deferred items filed: none required for this bounded slice.

## Risk Assessment
- Functional risk: low.
- Regression risk: low.
- Why: deterministic shared logic with explicit runtime and full listed-suite evidence.

## Final Decision
- Ready for Done: yes.
- Basis: all five pre-closure checks explicitly addressed and validation evidence is green.
