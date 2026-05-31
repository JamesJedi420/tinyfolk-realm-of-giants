# TIN-214 Slice B Kickoff (2026-05-31)

## Issue
- ID: TIN-214
- Title: Implement Tinyfolk stealth shrink state
- Slice: B (compatibility hardening for hiding/status precedence)
- Date: 2026-05-31
- Branch/PR: master (local-only)

## Slice Goal
- Harden stealth shrink compatibility so activation and runtime continuation respect hiding/status constraints with deterministic precedence and reason taxonomy.

## Bounded Scope (Slice B)
- Add activation-time precedence checks for:
  - hiding conflict
  - status conflict
- Add runtime invalidation checks while stealth is active for:
  - role drift
  - downed state
  - carried state
  - hiding conflict
  - status conflict
- Emit deterministic branch reasons for each invalidation path.
- Extend focused runtime spec coverage for each precedence/invalidation branch.

## Out Of Scope
- Client UX/VFX updates.
- Balancing detectability coefficients.
- New gameplay tools or economy coupling.
- Large cross-service rewires outside bounded query seams.

## Planned Deterministic Reasons
- Activation gating:
  - `hiding_forbidden`
  - `status_forbidden`
- Runtime cancellation branches:
  - `cancelled_role_mismatch`
  - `cancelled_downed`
  - `cancelled_carried`
  - `cancelled_hiding_conflict`
  - `cancelled_status_forbidden`

## Validation Plan
- Focused:
  - `lune run tests/tinyfolk_stealth_service_runtime_entrypoint.spec.luau`
- Changed-file gate:
  - `./scripts/run-validation.ps1 -ChangedOnly`
- Fresh full-suite checkpoint after batch:
  - `./scripts/run-tests.ps1`

## Exit Criteria
- Service enforces bounded hiding/status precedence at activation.
- Runtime tick cancels stealth on compatibility-breaking state transitions with deterministic reasons.
- Focused + changed-file + full-suite checkpoints pass.
