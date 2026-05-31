# TIN-222 Slice C Wildlife Interaction Outcomes Kickoff (2026-05-30)

## Issue
- ID: TIN-222
- Title: Implement neutral realm wildlife system
- Slice: C
- Date: 2026-05-30
- Status: Kickoff planned

## Why Slice C Exists
- Slice A established deterministic wildlife lifecycle ownership and habitat resolution.
- Slice B established world anchoring and disturbance ingress hardening with coarse clue boundaries.
- Remaining core acceptance gap is approved Giant interaction outcomes (feed, denial, dispersal) with bounded progression impact and deterministic controls.

## Fresh Baseline
- Slice B checkpoint evidence is recorded and validated.
- Full suite checkpoint: `./scripts/run-tests.ps1` pass.
- Linear has been updated with Slice B implementation + validation status.

## Proposed Bounded Scope
- Add explicit wildlife interaction outcome resolver in server runtime:
  - `feed_accepted`
  - `feed_denied`
  - `wildlife_dispersed`
- Add strict server-side gating for outcome eligibility:
  - role gate for Giant-only interaction path
  - wildlife state gate (active/disturbed only)
  - bounded cooldown/token cap to prevent runaway feed loops
- Add deterministic progression effect seam for accepted feed outcomes:
  - coarse, capped progression grant request through existing query seam hook when available
  - deterministic no-op fallback when progression seam is unavailable
- Add Tinyfolk-readable coarse aftermath clues for each outcome:
  - no actor id
  - no exact world positions
  - coarse zone/bucket metadata only

## Out of Scope
- Full predator-prey AI simulation.
- Combat/stat systems for wildlife entities.
- Client-heavy wildlife interaction UX.
- Economy balancing beyond bounded defaults and deterministic caps.

## Initial Implementation Plan
1. Add interaction request API surface in `NeutralWildlifeService`:
   - `RequestWildlifeInteraction(input)`
   - deterministic reason taxonomy for malformed/forbidden/ineligible states
2. Add interaction resolver helper with explicit transition matrix:
   - feed accepted -> terminal/despawn transition + capped progression hook
   - feed denied -> state preserved + coarse denial clue
   - dispersed -> disturbance/despawn transition based on state + coarse dispersal clue
3. Add bounded anti-snowball controls:
   - per-user or per-window feed cap in runtime config defaults
   - deterministic cooldown/tokens with diagnostics counters
4. Extend diagnostics snapshot:
   - interaction attempts/success/fail by reason
   - feed grants attempted/succeeded/capped
   - latest interaction outcome and wildlife id
5. Extend runtime entrypoint spec coverage:
   - valid Giant interaction accepted path
   - denied paths (non-Giant, out-of-state, cap reached, malformed)
   - progression hook calls only when eligible and capped
   - coarse clue payload checks (no actor/exact position)
6. Run focused tests, changed-only validation, and full suite checkpoint.

## Planned Reason Taxonomy (Draft)
- `request_invalid`
- `wildlife_id_invalid`
- `wildlife_not_found`
- `actor_user_id_invalid`
- `actor_role_forbidden`
- `wildlife_ineligible`
- `interaction_outcome_invalid`
- `feed_cap_reached`
- `feed_accepted`
- `feed_denied`
- `wildlife_dispersed`

## Validation Expectations
- Focused specs:
  - `lune run tests/wildlife_state.spec.luau`
  - `lune run tests/neutral_wildlife_service_runtime_entrypoint.spec.luau`
- Changed-file gate:
  - `./scripts/run-validation.ps1 -ChangedOnly`
- Full regression checkpoint:
  - `./scripts/run-tests.ps1`

## Risks and Controls
- Risk: feed interaction creates Giant snowball progression.
  - Control: strict per-window cap/cooldown and deterministic diagnostics.
- Risk: interaction clues leak tracking precision.
  - Control: coarse zone/bucket metadata only; test assertions for omissions.
- Risk: role-gate regressions allow unauthorized interaction.
  - Control: deterministic role gate checks and explicit negative-path specs.

## Exit Criteria (Slice C)
- Approved interaction outcomes implemented with deterministic transitions.
- Feed progression effect bounded and capped, with no-op fallback when seam unavailable.
- Coarse aftermath clues emitted for outcomes without precise leakage.
- Focused specs, changed-only validation, and full-suite checkpoint all pass.
