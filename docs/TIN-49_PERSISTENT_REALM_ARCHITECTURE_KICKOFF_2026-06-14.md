# TIN-49 Persistent Realm Architecture Kickoff (2026-06-14)

## Issue

- ID: TIN-49
- Title: Define persistent realm architecture
- Milestone: Persistence and Ownership
- Linear: https://linear.app/spectranoir/issue/TIN-49/define-persistent-realm-architecture

## Goal

Establish the canonical architecture contract for shared Tinyfolk hub servers vs per-Giant persistent realm servers, persistence partitions, controlled transfer ingress, and player location category — without implementing cross-server transfer runtime.

## Context

Capture, Rescue, and Routing milestone work (capture, transfer, ransom, abuse detection/enforcement, moderation hooks) is largely complete. TIN-49 unblocks the persistence / cross-server dependency chain before deeper transfer implementation in TIN-11 and TIN-106.

## Scope

- Author `docs/TIN-49_PERSISTENT_REALM_ARCHITECTURE.md` as the canonical architecture record.
- Map acceptance criteria to world topology, profile partitions, controlled transfer shell, and location category.
- Document prototype-vs-target server split and existing runtime seam evidence.
- Record downstream handoff boundaries for TIN-11, TIN-106, and TIN-241.

## Boundary

- Architecture definition and documentation only.
- No cross-server transfer implementation.
- No new save-pipeline or handoff-token runtime.
- No `realmAssignment` state machine (TIN-11).
- No durable realm session record implementation (TIN-106).

## Inspect first

- `docs/GAME_SPEC.md` (shared world vs Giant realm)
- `docs/PROFILE_OWNERSHIP_DECISION.md`
- `docs/SYSTEM_BOUNDARIES.md`
- `docs/TIN-174_EVENT_STATE_OWNERSHIP_MODEL.md`
- `docs/TIN-75_ENFORCEMENT_SLICE_KICKOFF_2026-06-15.md` (enforcement context)
- `docs/TIN-117_REALM_ADMISSION_QUEUE_CLOSURE_2026-05-25.md`
- `docs/TIN-67_CROSS_SERVER_TRANSFER_ORCHESTRATION_CLOSURE_2026-06-11.md`

## Validation

Doc/review gate against TIN-49 acceptance criteria. No runtime tests unless acceptance criteria add bounded prototypes.

## Deferred

- TIN-11 realm transfer state model implementation.
- TIN-106 handoff tokens and durable realm session records.
- TIN-241 cross-realm XP sync.
- Explicit `realmAssignment` player-profile namespace consolidation.
