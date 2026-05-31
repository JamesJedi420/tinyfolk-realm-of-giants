# TIN-214 Slice B Closure-Style Evidence (2026-05-31)

## Issue
- ID: TIN-214
- Title: Implement Tinyfolk stealth shrink state
- Slice: B (compatibility hardening for hiding/status precedence)
- Date: 2026-05-31
- Branch/PR: master (local-only)

## Slice B Summary
- Added bounded compatibility precedence checks for stealth activation against hiding and status constraints.
- Added deterministic runtime invalidation branches for compatibility-breaking state transitions while stealth is active.
- Extended focused runtime coverage to assert branch-specific reasons for both activation rejection and active-state cancellation paths.

## Implementation Evidence
- src/ServerScriptService/Services/TinyfolkStealthService.server.luau
  - Added compatibility resolvers:
    - `resolveHidingServiceApi`
    - `resolveStatusServiceApi`
  - Added bounded compatibility helpers:
    - `isPlayerHiding`
    - `isStatusStealthAllowed`
  - Activation precedence hardening (`RequestStealthShrink`):
    - rejects when hiding is active: `hiding_forbidden`
    - rejects when real status snapshot blocks stealth (stun active): `status_snapshot_forbidden`
    - rejects when status resolver blocks stealth: `status_forbidden` (or provided deterministic status reason)
  - Runtime invalidation hardening (`tickStealthShrink` + `checkInvalidState`):
    - role drift -> `cancelled_role_mismatch`
    - downed -> `cancelled_downed`
    - carried -> `cancelled_carried`
    - hiding conflict -> `cancelled_hiding_conflict`
    - status snapshot conflict (stun active) -> `cancelled_status_snapshot_forbidden`
    - status conflict -> `cancelled_status_forbidden`
- src/ServerScriptService/Services/TinyfolkStatusService.server.luau
  - Added query API exposure for real snapshot integration:
    - `GetStatusSnapshot(userId, now?)`
  - Enables cross-service status gating from real timed-condition state instead of resolver-only seams.
- tests/tinyfolk_stealth_service_runtime_entrypoint.spec.luau
  - Added coverage for activation rejection precedence:
    - interaction conflict
    - hiding conflict
    - status snapshot conflict
    - status conflict
  - Added coverage for active-state cancellation reasons:
    - role drift
    - downed
    - carried
    - hiding conflict
    - status snapshot conflict
    - status conflict
  - Added explicit multi-conflict precedence matrix assertions for deterministic ordering when multiple conflicts are simultaneously true.
  - Updated diagnostics expectations to match expanded invalidation coverage.

## Validation Evidence

### Focused Spec
- `lune run tests/tinyfolk_stealth_service_runtime_entrypoint.spec.luau` -> `tinyfolk_stealth_service_runtime_entrypoint: all checks passed`

### Focused Precedence Matrix (Simultaneous Conflicts)
- Activation ordering verified:
  - `interaction_forbidden` takes precedence over hiding/status conflicts.
  - `hiding_forbidden` takes precedence over `status_forbidden` when both are true.
  - `status_snapshot_forbidden` takes precedence over `status_forbidden` when both status blockers are true.
- Runtime invalidation ordering verified:
  - `cancelled_invalid_state` (custom resolver) takes precedence over all runtime branch checks.
  - `cancelled_role_mismatch` takes precedence over downed/carried/hiding/status.
  - `cancelled_downed` takes precedence over carried/hiding/status.
  - `cancelled_carried` takes precedence over hiding/status.
  - `cancelled_hiding_conflict` takes precedence over `cancelled_status_forbidden`.
  - `cancelled_status_snapshot_forbidden` takes precedence over `cancelled_status_forbidden` when both status blockers are true.

### Changed-file Validation Gate
- `./scripts/run-validation.ps1 -ChangedOnly` -> pass
  - `stylua` pass
  - `selene` pass
  - `luau-lsp` pass

### Full Regression Suite (Fresh Checkpoint)
- `./scripts/run-tests.ps1` (2026-05-31) -> pass (exit code 0)
- Representative pass markers captured from suite output:
  - `neutral_wildlife_service_runtime_entrypoint: all checks passed`
  - `realm_admission_queue_service_runtime_entrypoint: all checks passed`
  - `headless_match_simulation: all checks passed`

## Deterministic Reason Coverage (Slice B Delta)
- Activation precedence:
  - `hiding_forbidden`
  - `status_snapshot_forbidden`
  - `status_forbidden`
- Runtime invalidation branches:
  - `cancelled_role_mismatch`
  - `cancelled_downed`
  - `cancelled_carried`
  - `cancelled_hiding_conflict`
  - `cancelled_status_snapshot_forbidden`
  - `cancelled_status_forbidden`

## Boundary Notes
- Included in Slice B:
  - activation-time compatibility precedence (hiding/status)
  - deterministic branch-specific runtime invalidation reasons
  - focused branch coverage updates
- Explicitly out of scope in Slice B:
  - client UX/VFX
  - balancing passes
  - broad cross-service API redesign

## Pre-Closure Checklist (Slice B Checkpoint)

### 1. Implementation Gaps
- Checked: yes.
- Covered in this slice: hiding/status activation precedence and deterministic runtime invalidation reason branches.
- Remaining for future slices: broader inter-service integrations and gameplay tuning.

### 2. Missing Validation or Weak Evidence
- Checked: yes.
- Evidence present: focused spec pass, changed-file gate pass, fresh full-suite checkpoint pass.
- Residual risk: low for bounded Slice B scope.

### 3. Required Document Updates
- Checked: yes.
- Added Slice B kickoff and this Slice B evidence document.

### 4. Related Issue Boundary Problems
- Checked: yes.
- Evidence remains bounded to TIN-214 Slice B and does not claim sibling issue completion.

### 5. Remaining Cleanup
- Checked: yes.
- No blocking cleanup identified for this bounded checkpoint.

## Slice B Checkpoint Decision
- Slice B checkpoint status: in progress with this validated compatibility-hardening increment complete.
- Recommended next step: continue Slice B with next bounded compatibility sub-slice or prepare Slice C kickoff criteria.
