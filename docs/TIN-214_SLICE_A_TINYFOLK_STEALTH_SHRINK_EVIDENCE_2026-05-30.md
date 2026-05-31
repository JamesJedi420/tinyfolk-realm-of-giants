# TIN-214 Slice A Closure-Style Evidence (2026-05-30)

## Issue
- ID: TIN-214
- Title: Implement Tinyfolk stealth shrink state
- Slice: A (deterministic shared state + server runtime seam)
- Date: 2026-05-30
- Branch/PR: master (local-only)
- Evidence commit anchor: `674cbd6e`

## Slice A Summary
- Added a deterministic shared stealth shrink state owner with bounded activation, cancellation, expiry, and snapshot shaping.
- Added a server-authoritative runtime seam that publishes request/cancel/query/tick APIs through `_TinyfolkStealthService_QueryAPI`.
- Enforced deterministic admission and cancellation reasons for invalid requests, role gating, interaction gating, blocked major actions, explicit cancel, invalid-state cancellation, and expiry.
- Added focused state and runtime-entrypoint specs covering the bounded Slice A acceptance surface.

## Implementation Evidence
- src/ReplicatedStorage/Shared/TinyfolkStealth/StealthShrinkState.luau
  - Added pure state transitions for:
    - activation
    - explicit cancel
    - expiry tick
    - immutable snapshot output
  - Tracks deterministic reason/state fields:
    - `isActive`
    - `startedAt`
    - `endsAt`
    - `lastReason`
    - `lastChangedAt`
    - `remainingSeconds`
- src/ServerScriptService/Services/TinyfolkStealthService.server.luau
  - Added runtime query API seam:
    - `RequestStealthShrink`
    - `CancelStealthShrink`
    - `CanPerformMajorAction`
    - `GetStealthShrinkSnapshot`
    - `GetStealthShrinkDiagnostics`
    - `TickStealthShrink`
    - `ConfigureForTests`
    - `ResetForTests`
  - Added deterministic ingress checks for:
    - invalid request payloads
    - invalid user id
    - non-Tinyfolk role rejection
    - interaction permission rejection
    - duplicate activation rejection
  - Added cancellation paths for:
    - explicit request cancel
    - blocked major action attempt while active
    - invalid runtime state
    - duration expiry
  - Added diagnostics counters for activation, cancellation, expiry, invalid-state cancellation, invalid-action cancellation, and last observed reason/action.
  - Added test-environment support for `_G.game` and `_TinyfolkStealth_TestModules` fallback injection.
- tests/stealth_shrink_state.spec.luau
  - Covers activation, duplicate activation rejection, pre-expiry tick behavior, expiry, explicit cancel, and snapshot reason tracking.
- tests/tinyfolk_stealth_service_runtime_entrypoint.spec.luau
  - Covers request validation, role gating, interaction gating, duplicate activation rejection, blocked major action cancellation, invalid-state cancellation, snapshot visibility, and query API publication.

## Validation Evidence

### Worktree State
- `git rev-parse --short HEAD` -> `674cbd6e`
- `git status --short --untracked-files=all` -> clean worktree

### Focused Specs
- `lune run tests/stealth_shrink_state.spec.luau` -> `stealth_shrink_state: all checks passed`
- `lune run tests/tinyfolk_stealth_service_runtime_entrypoint.spec.luau` -> `tinyfolk_stealth_service_runtime_entrypoint: all checks passed`

### Changed-file Validation Gate
- `./scripts/run-validation.ps1 -ChangedOnly` -> `[validate] no changed .luau files under src/tests`
- Interpretation: the worktree was already clean at the evidence checkpoint, so the changed-only gate had no eligible Luau targets to re-check.

### Full Regression Suite
- `./scripts/run-tests.ps1` (2026-05-31) -> pass
- Includes both stealth-focused suites in the full run:
  - `stealth_shrink_state: all checks passed`
  - `tinyfolk_stealth_service_runtime_entrypoint: all checks passed`
- Residual-risk caveat for missing full-suite coverage is cleared for this checkpoint.

## Deterministic Reason Taxonomy Covered In Slice A
- `request_invalid`
- `user_id_invalid`
- `role_forbidden`
- `interaction_forbidden`
- `already_active`
- `accepted`
- `cancelled_by_request`
- `cancelled_invalid_action`
- `cancelled_invalid_state`
- `expired`
- `not_active`

## Boundary Notes
- Included in Slice A:
  - deterministic stealth shrink state lifecycle
  - server-owned request/cancel/tick/query seam
  - blocked major-action cancellation gate
  - invalid-state cancellation path
  - focused deterministic spec coverage
- Explicitly out of scope in Slice A:
  - client VFX/animation
  - stealth balancing pass
  - tool-cache/proxy coupling work
  - broader hiding-system integration beyond bounded compatibility seams

## Pre-Closure Checklist (Slice A Checkpoint)

### 1. Implementation Gaps
- Checked: yes.
- Covered for this slice: deterministic state lifecycle, request/cancel/query seam, blocked-action gate, invalid-state cancellation, diagnostics, focused seam/state coverage.
- Remaining for later slices: richer integration with adjacent gameplay systems and broader balancing/UX work.

### 2. Missing Validation or Weak Evidence
- Checked: yes.
- Evidence present: focused stealth specs and full regression suite checkpoint.
- Residual risk: low, bounded to future changes after this checkpoint.

### 3. Required Document Updates
- Checked: yes.
- Added kickoff and this Slice A evidence artifact.

### 4. Related Issue Boundary Problems
- Checked: yes.
- Evidence is bounded to TIN-214 Slice A and does not claim sibling issue completion.

### 5. Remaining Cleanup
- Checked: yes.
- No blocking cleanup identified inside the bounded Slice A runtime/state seam.
- Recommended follow-up: keep evidence in sync if new Slice B+ changes land before closure.

## Slice A Checkpoint Decision
- Slice A checkpoint status: implementation complete with focused evidence.
- Recommended next step: run full regression suite, then proceed to Slice B planning/implementation.