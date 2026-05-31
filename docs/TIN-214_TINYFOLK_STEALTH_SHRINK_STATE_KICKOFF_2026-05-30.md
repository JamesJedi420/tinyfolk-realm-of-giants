# TIN-214 Tinyfolk Stealth Shrink State Kickoff (2026-05-30)

## Issue
- ID: TIN-214
- Title: Implement Tinyfolk stealth shrink state
- Linear: https://linear.app/spectranoir/issue/TIN-214/implement-tinyfolk-stealth-shrink-state
- Status: Backlog

## Why This Is The Next Best Implementation
- The issue has a complete structured brief (Goal/Scope/Constraints/Acceptance), so planning and validation boundaries are explicit.
- Existing server-authoritative seams already exist for compatibility requirements:
  - Tinyfolk hiding (`TinyfolkHidingService` / `HidingState`)
  - Tinyfolk status and trail/warning projections (`TinyfolkStatusService` + timed status projections)
  - escape/capture/rescue gating paths already model deterministic blocked reasons.
- This slice is bounded and incremental: it extends current state machines instead of requiring missing foundational systems.

## Proposed Bounded Scope (Slice A)
- Add server-owned stealth shrink runtime state with deterministic transitions:
  - inactive -> active -> ended/cancelled
- Add activation path through a bounded request seam (`RequestStealthShrink`) with strict role and interaction validity checks.
- Add explicit blocked-action gate while active for major actions:
  - objective work
  - final-exit opening
  - rescue contract request
  - heavy tool interactions
- Add deterministic cancellation triggers:
  - duration expiry
  - explicit cancel
  - invalid action attempt while active
  - state invalidation (downed, carried, contained, role mismatch)
- Add coarse observability/query seam:
  - `GetStealthShrinkSnapshot`
  - deterministic reason taxonomy for accepted/rejected/cancelled paths.

## Out Of Scope (Slice A)
- Rich client VFX/animation work.
- New stealth-specific gameplay tools/economy.
- Full balancing pass for detectability coefficients.
- Proxy/tool-cache coupling work from other issues.

## Initial Implementation Plan
1. Add shared deterministic state module:
- `src/ReplicatedStorage/Shared/TinyfolkStealth/StealthShrinkState.luau`
- Pure transition logic + snapshot + reason taxonomy.

2. Add server runtime seam:
- `src/ServerScriptService/Services/TinyfolkStealthService.server.luau`
- Query API publication:
  - `RequestStealthShrink`
  - `CancelStealthShrink`
  - `GetStealthShrinkSnapshot`
  - `GetStealthShrinkDiagnostics`
  - `TickStealthShrink`
  - `ConfigureForTests` / `ResetForTests`

3. Add compatibility gates:
- integrate with existing role/hiding/status checks via query APIs where available
- enforce blocked major-action reasons while shrink is active
- maintain server-authoritative cancellation on invalid state transitions.

4. Add focused tests:
- `tests/stealth_shrink_state.spec.luau`
- `tests/tinyfolk_stealth_service_runtime_entrypoint.spec.luau`
- cover activation, blocked actions, cancellation triggers, expiry, and diagnostics parity.

5. Validation and regression gates:
- `scripts/run-validation.ps1 -ChangedOnly`
- focused stealth specs
- `scripts/run-tests.ps1`

## Draft Deterministic Reason Taxonomy
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

## Risks and Controls
- Risk: stealth becomes full-action free escape mode.
  - Control: explicit blocked-action gate and cancellation on invalid action attempts.
- Risk: stealth bypasses carry/containment/final-exit boundaries.
  - Control: explicit state-invalidation cancellation path and reason assertions.
- Risk: overlap with hiding system creates contradictory states.
  - Control: deterministic compatibility precedence and focused integration assertions.

## Exit Criteria (Slice A)
- Server-authoritative stealth shrink state and request/cancel/query seams implemented.
- Major blocked actions deterministically rejected while active.
- Defined cancellation/expiry triggers implemented and test-covered.
- Focused specs, changed-file validation, and full-suite checkpoint pass.
