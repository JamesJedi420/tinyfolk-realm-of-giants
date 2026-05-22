# Tinyfolk Status Require Seam Closure (2026-05-22)

## Issue
- ID: TIN-165/TIN-164 timed-condition runtime seam follow-up
- Title: Harness-safe TinyfolkStatusService module require seam
- Date Closed: 2026-05-22
- Owner: [fill]
- Branch/PR: [fill]

## Summary
- Implemented a harness-safe module loader seam in `TinyfolkStatusService.server.luau` to prevent `require(nil)` when mocked runtime trees omit one or more TinyfolkStatus child modules.
- Preserved Roblox runtime behavior by prioritizing instance/module-node requires and only using string fallback paths in harness shapes.
- Scope stayed loader-only; no intended gameplay rule or balance changes.

## Root Cause
- `tests/timed_condition_states_runtime_entrypoint.spec.luau` fixture did not include `GiantThreatStageLogic` under `Shared.TinyfolkStatus`.
- `src/ServerScriptService/Services/TinyfolkStatusService.server.luau` loaded TinyfolkStatus modules with direct `WaitForChild(...):WaitForChild(...)` instance requires.
- In this fixture shape, one lookup resolved to `nil`, causing `require(nil)` and failing the timed-condition runtime entrypoint.

## Validation Evidence
- Before-fix failure signature (timed-condition seam):
  - Command: `lune run tests/timed_condition_states_runtime_entrypoint.spec.luau`
  - Observed error: `__mlua_require:4: bad argument #1 to 'require' (string expected, got nil)`
  - Stack anchor: `src/ServerScriptService/Services/TinyfolkStatusService.server:11`
- Targeted regression:
  - `lune run tests/timed_condition_states_runtime_entrypoint.spec.luau`
  - Result: all checks passed.
- Capture safety check:
  - `lune run tests/capture_state.spec.luau`
  - Result: `23 passed, 0 failed`.
- Capture runtime check:
  - `lune run tests/capture_service_runtime_entrypoint.spec.luau`
  - Result: all checks passed.
- Full suite:
  - `./scripts/run-tests.ps1`
  - Result: all listed suites passed, including `timed_condition_states_runtime_entrypoint`.

## Command Log Snapshot (Post-Fix)
- `lune run tests/timed_condition_states_runtime_entrypoint.spec.luau` -> `timed_condition_states_runtime_entrypoint: all checks passed`
- `lune run tests/capture_state.spec.luau` -> `23 passed, 0 failed`
- `lune run tests/capture_service_runtime_entrypoint.spec.luau` -> `capture_service_runtime_entrypoint: all checks passed`
- `./scripts/run-tests.ps1` -> pass markers include:
  - `timed_condition_states_runtime_entrypoint: all checks passed`
  - `capture_service_runtime_entrypoint: all checks passed`
  - `headless_match_simulation: all checks passed`

## Pre-Closure Checklist

### 1. Implementation Gaps
- Checked: yes.
- Notes: loader seam covers module node present, module node as string path, and missing node fallback path.
- Remaining gap follow-up: none identified.

### 2. Validation and Evidence Strength
- Checked: yes.
- Direct criteria coverage:
  - timed-condition runtime seam no longer faults -> `tests/timed_condition_states_runtime_entrypoint.spec.luau`.
  - no capture-slice regression from seam fix -> `tests/capture_state.spec.luau` and `tests/capture_service_runtime_entrypoint.spec.luau`.
  - no cross-slice regression in listed suite -> `scripts/run-tests.ps1`.
- Residual testing risk: low (harness seam change with full listed suite green).

### 3. Required Document Updates
- Checked: yes.
- Updated docs:
  - `docs/TINYFOLK_STATUS_REQUIRE_SEAM_CLOSURE_2026-05-22.md` (this record).
  - pointer added in `docs/SYSTEM_BOUNDARIES.md`.

### 4. Related Issue Boundary and Dependencies
- Checked: yes.
- Included in this closure:
  - TinyfolkStatusService module loading seam for mixed Roblox runtime and Lune harness resolution.
- Explicitly out of scope:
  - status-effect tuning, fear thresholds, HUD presentation changes, score/capture semantics.
- Related dependency notes:
  - fixture module tree completeness remains recommended, but seam now fails safe with deterministic fallback.

### 5. Remaining Cleanup
- Checked: yes.
- Dead code or TODOs introduced: none.
- Deferred items filed: none required for this closure.

## Risk Assessment
- Functional risk: low.
- Regression risk: low.
- Why: loader-only change, no gameplay-logic branch edits, targeted and full-suite validation green.

## Final Decision
- Ready for Done: yes.
- Basis: all five pre-closure checks addressed and listed test evidence is green.
