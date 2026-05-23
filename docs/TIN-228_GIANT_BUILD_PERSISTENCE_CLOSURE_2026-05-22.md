# TIN-228 GiantBuild Persistence Closure (2026-05-22)

## Issue
- ID: TIN-228
- Title: Stabilize GiantBuild save/apply persistence integration and gateway coverage
- Date Closed: 2026-05-22
- Owner: [fill]
- Branch/PR: master (local-only)

## Summary
- Hardened GiantBuild giant-realm persistence handling around save-root construction and apply-time failure paths.
- Save snapshots now exclude snare-trap-only placement records from persisted placed-structure output.
- Apply-time failures from emergency reinforcement, shrine persistence, or rescue persistence now reject without partially replacing live GiantBuild structure registry or Workspace artifacts.
- `ProfilePersistenceGateway` coverage now includes malformed giant-realm save-root handling through the existing `BuildSaveSnapshot` / `ApplySaveSnapshot` seam.
- Scope remained persistence-boundary hardening only; no intended gameplay tuning or balance changes.

## Root Cause / Motivation
- GiantBuild persistence needed stronger ownership-boundary guarantees:
  - save roots should not treat snare-trap-only placement state as general placed structures
  - downstream persistence apply failures should not leave live GiantBuild state partially mutated
  - malformed giant-realm save roots returned from the owner layer should fail deterministically through gateway/apply validation

## Implementation
- `src/ServerScriptService/Services/GiantBuildModeService.server.luau`
  - Added saveable-structure filtering for `BuildSaveSnapshot`.
  - Preserved live registry/artifacts when downstream persistence apply seams reject.
  - Switched in-place table clearing to key-collection-first clearing for safer mutation.
- `tests/giant_build_mode_service_runtime_entrypoint.spec.luau`
  - Added save/apply coverage for reinforcement, shrine, and rescue apply failure handling.
  - Added cleanup apply coverage before repeated resource exhaustion validation.
- `tests/profile_persistence_gateway.spec.luau`
  - Added malformed giant-realm save-root load coverage through `LoadGiantRealmProfile`.

## Validation Evidence
- Focused runtime coverage:
  - `lune run tests/giant_build_mode_service_runtime_entrypoint.spec.luau`
  - Result: `giant_build_mode_service_runtime_entrypoint: all checks passed`
- Focused gateway coverage:
  - `lune run tests/profile_persistence_gateway.spec.luau`
  - Result: `profile_persistence_gateway: all checks passed`
- Full listed suite:
  - `./scripts/run-tests.ps1`
  - Result: exit code `0`
  - Pass markers included:
    - `capture_service_runtime_entrypoint: all checks passed`
    - `timed_condition_states_runtime_entrypoint: all checks passed`
    - `headless_match_simulation: all checks passed`
    - `rescue_contract_service_runtime_entrypoint: all checks passed`
    - `emergency_reinforcement_service_runtime_entrypoint: all checks passed`

## Command Log Snapshot
- `lune run tests/giant_build_mode_service_runtime_entrypoint.spec.luau` -> `giant_build_mode_service_runtime_entrypoint: all checks passed`
- `lune run tests/profile_persistence_gateway.spec.luau` -> `profile_persistence_gateway: all checks passed`
- `./scripts/run-tests.ps1` -> listed suite passed with exit code `0`

## Commits
- `2556c875` `stabilize giant build persistence apply save coverage`

## Pre-Closure Checklist

### 1. Implementation Gaps
- Checked: yes.
- Notes: this slice covers saveable-structure filtering, downstream apply rejection preservation, and malformed save-root gateway coverage.
- Remaining gap follow-up: none identified within this bounded persistence slice.

### 2. Validation and Evidence Strength
- Checked: yes.
- Direct criteria coverage:
  - GiantBuild save/apply persistence runtime behavior -> `tests/giant_build_mode_service_runtime_entrypoint.spec.luau`
  - malformed giant-realm gateway load path -> `tests/profile_persistence_gateway.spec.luau`
  - cross-slice regression gate -> `scripts/run-tests.ps1`
- Residual testing risk: low.

### 3. Required Document Updates
- Checked: yes.
- Updated docs:
  - `docs/TIN-228_GIANT_BUILD_PERSISTENCE_CLOSURE_2026-05-22.md` (this record)
  - pointer added in `docs/SYSTEM_BOUNDARIES.md`

### 4. Related Issue Boundary and Dependencies
- Checked: yes.
- Included in this closure:
  - GiantBuild save/apply persistence hardening
  - ProfilePersistenceGateway malformed giant realm load coverage
- Explicitly out of scope:
  - TinyfolkStatus require seam work
  - gameplay balance changes
  - broader persistence migration or multi-realm support
- Dependency notes:
  - `GiantRealmSaveSchema` remains the save-root validation authority
  - `ProfilePersistenceGateway` remains the gameplay-facing persistence boundary

### 5. Remaining Cleanup
- Checked: yes.
- Dead code or TODOs introduced: none identified.
- Deferred items filed: none required for this bounded slice.

## Risk Assessment
- Functional risk: low.
- Regression risk: low.
- Why: bounded persistence-surface hardening with focused runtime coverage and green listed suite.

## Final Decision
- Ready for Done: yes.
- Basis: targeted persistence specs pass, the listed suite passes, and all five pre-closure checks are explicitly addressed above.