# TIN-222 Slice B Wildlife World Anchoring + Ingress Kickoff (2026-05-30)

## Issue
- ID: TIN-222
- Title: Implement neutral realm wildlife system
- Slice: B
- Date: 2026-05-30
- Status: Kickoff planned

## Why Slice B Exists
- Slice A established deterministic wildlife state ownership, bounded lifecycle rules, and workspace-node habitat source resolution.
- Remaining value is to harden world anchoring and ingress behavior so wildlife disturbances feel connected to real map anchor points while preserving anti-wallhack clue boundaries.
- This kickoff defines a bounded implementation batch that builds directly on the validated Slice A baseline without broad AI/economy expansion.

## Fresh Baseline Checkpoint (Pre-Slice B)
- Full suite command run on 2026-05-30:
  - ./scripts/run-tests.ps1 -> pass
- Fresh pass evidence includes:
  - wildlife_state: all checks passed
  - neutral_wildlife_service_runtime_entrypoint: all checks passed
  - headless_match_simulation: all checks passed
  - notification_rate_guard: all checks passed
  - system_announcement_service_runtime_entrypoint: all checks passed

## Proposed Bounded Scope
- Add a world-anchor projection layer for wildlife habitat nodes:
  - deterministic anchor identity per habitat group
  - bounded coarse zone labels for clue output
  - strict fallback when anchors are missing/unreadable
- Add bounded disturbance ingress hardening:
  - optional proximity-gated disturbance acceptance against habitat anchor centers
  - deterministic rejection reasons for invalid/out-of-bounds attempts
  - no actor/position leakage into clue payloads
- Add runtime diagnostics expansion:
  - anchor resolution counts and fallback reason visibility
  - disturbance gate counters (accepted/rejected by reason)
- Preserve existing deterministic lifecycle cap/respawn behavior and avoid broad system rewrites.

## Out of Scope
- Full wildlife AI behavior trees/pathfinding/combat.
- Rich client wildlife UI or cinematic encounter systems.
- Reward economy/balance iteration.
- Cross-session persistence and replay tooling.

## Initial Implementation Plan
1. Add anchor extraction helper in NeutralWildlifeService to map habitat groups to coarse anchor descriptors (zoneId + center bucket), with strict nil-safe fallback.
2. Extend habitat group snapshots/records with anchor metadata needed for bounded disturbance checks.
3. Add optional disturbance distance guard against anchor center or habitat node center when available, with deterministic reason taxonomy.
4. Extend clue emission metadata to include only coarse zone/anchor identifiers (no exact positions, no actor identity).
5. Extend focused runtime spec coverage for:
   - anchor resolution success/fallback
   - in-range vs out-of-range disturbance acceptance
   - diagnostics counter updates and reason parity
6. Run focused specs, changed-only validation, and a full suite checkpoint before Slice B closure recommendation.

## Validation Expectations
- scripts/run-validation.ps1 -ChangedOnly
- Focused specs:
  - tests/wildlife_state.spec.luau
  - tests/neutral_wildlife_service_runtime_entrypoint.spec.luau
- Fresh full suite checkpoint:
  - scripts/run-tests.ps1

## Risks and Controls
- Risk: Anchor-driven logic introduces map-coupling instability.
  - Control: deterministic fallback to config-only behavior and explicit diagnostics source tagging.
- Risk: Disturbance gate causes false negatives and blocks expected interactions.
  - Control: optional/bounded guard with deterministic reasons and focused threshold tests.
- Risk: Clue payload accidentally leaks exact Giant/Tinyfolk context.
  - Control: enforce coarse zone-level payloads only; assert omission in runtime specs.

## Exit Criteria (Slice B)
- Anchor resolution seam implemented with deterministic fallback behavior.
- Disturbance ingress hardening implemented with deterministic reason taxonomy.
- Coarse clue shaping preserved and validated.
- Focused specs, changed-file validation, and full suite pass evidence recorded.
