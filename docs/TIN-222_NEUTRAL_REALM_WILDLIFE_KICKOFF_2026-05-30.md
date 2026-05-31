# TIN-222 Neutral Realm Wildlife Kickoff (2026-05-30)

## Issue
- ID: TIN-222
- Title: Implement neutral realm wildlife system
- Linear state: Backlog
- Project: Tinyfolk: Realm of Giants

## Why This Is The Next Best Implementation Target
- It is a true net-new backlog slice with clear acceptance criteria and no in-progress overlap in repo docs.
- It leverages recently completed realm metadata/theme/status/event foundations without requiring deep rewrites.
- It can be delivered as a bounded server-authoritative system with deterministic limits (spawn density, respawn cadence, clue fidelity).

## Note On TIN-232 vs TIN-233
- Linear currently shows `TIN-232` with the same title/scope as repo active follow-up docs under `TIN-233`.
- Repo evidence indicates the ingress/scheduler hardening stream is already actively implemented and close to closure.
- Recommendation: treat TIN-232/TIN-233 as an issue-reconciliation/admin step, not the next net-new implementation slice.

## Proposed Bounded Scope (Slice A)
- Add deterministic wildlife runtime state owner seam (server-only).
- Add bounded spawn-group schema and habitat candidate selection per realm.
- Add wildlife lifecycle loop with strict limits:
  - max active wildlife count
  - deterministic respawn interval window
  - deterministic despawn/expiry reasons
- Add Tinyfolk-readable coarse clue emission for lifecycle/interaction aftermath (no exact Giant tracing).
- Add read-only query diagnostics for debug/runtime verification.

## Out of Scope (Slice A)
- Full creature AI/combat ecosystem.
- Rich client wildlife UI and cinematic behavior trees.
- Broad reward economy tuning and progression balancing.
- Persistence of wildlife entities across sessions.

## Initial Implementation Plan
1. Shared deterministic state logic
- Add `Shared/GiantRealm/WildlifeState` with pure-Luau deterministic transitions:
  - spawn
  - despawn
  - expire
  - disturb
  - feed-denied/feed-accepted hooks (placeholder-compatible)
- Enforce schema validation for wildlife records and reason taxonomy.

2. Server runtime service seam
- Add `ServerScriptService/Services/NeutralWildlifeService.server.luau`:
  - startup spawn seeding from realm metadata + habitat config
  - tick/update lifecycle loop
  - bounded clue event emission through existing event-log seam when available
  - query API:
    - `GetWildlifeSnapshot`
    - `GetWildlifeDiagnostics`
    - `RequestWildlifeDisturbance` (bounded server ingress)

3. Minimal realm metadata compatibility
- Add optional wildlife habitat config references that are validated but non-breaking when absent.
- Use safe defaults if realm metadata does not yet provide wildlife candidates.

4. Anti-wallhack clue shaping
- Emit coarse clues only:
  - habitat disturbed
  - noise event in coarse zone id
  - wildlife missing/departed
- Exclude exact actor ids and exact world positions from consumer-facing payloads.

5. Focused tests and suite wiring
- Add focused specs:
  - `tests/wildlife_state.spec.luau`
  - `tests/neutral_wildlife_service_runtime_entrypoint.spec.luau`
- Extend existing observability/service integration specs only where needed.
- Add new spec to `scripts/run-tests.ps1` explicit list.

## Validation Expectations
- `scripts/run-validation.ps1 -ChangedOnly`
- Focused wildlife state + runtime entrypoint specs
- Full suite: `scripts/run-tests.ps1`

## Risks And Controls
- Risk: wildlife count/perf drift under long sessions.
  - Control: strict active caps + deterministic tick budget + lifecycle expiry rules.
- Risk: clue system becomes wallhack-like Giant tracker.
  - Control: coarse zone-level clue payloads; no exact position/actor outputs.
- Risk: metadata coupling blocks rollout on missing configs.
  - Control: optional metadata fields with bounded defaults and compatibility fallbacks.

## Exit Criteria (Slice A)
- Wildlife runtime state owner seam implemented with deterministic limits.
- Realm-compatible spawn selection and lifecycle flow implemented.
- Coarse Tinyfolk-readable clue emission implemented with privacy boundaries.
- Focused wildlife specs and full suite pass evidence recorded.
