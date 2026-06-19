# TIN-31 Tinyfolk AI Job Scheduling Kickoff (2026-06-19)

## Issue

- ID: TIN-31
- Title: Implement Tinyfolk AI job scheduling
- Milestone: Progression, Economy, and Loadouts
- Linear: https://linear.app/spectranoir/issue/TIN-31/implement-tinyfolk-ai-job-scheduling

## Goal

Add a bounded, server-owned job scheduling layer that assigns **live player Tinyfolk** to valid specialist production jobs and general-haul labor jobs. This slice establishes scheduling state and assignment policy; it does **not** add NPC pathfinding, hauling route AI (TIN-32), or presentation polish (TIN-33).

## Problem (current gap)

- **TIN-37** gates production on completed labor work actions and validates specialist/action pairing (`LaborActionState`, `StationService`, `ShrineService`).
- **Specialist assignment** is reactive: `StationService.ensureInteractionSpecialistAssignment` and player `F` interactions call `SpecialistAssignmentService.AssignForInteraction` at use time.
- There is **no** proactive scheduler that discovers open work, matches eligible Tinyfolk, rejects conflicts, or exposes scheduling debug state.
- `GAME_SPEC.md` and `AGENT_RULES.md` correctly state full job scheduling is **not** implemented.

## Slice A boundary (this issue)

### In scope

1. **Pure scheduling logic** in `Shared/GiantRealm/TinyfolkJobSchedulingState.luau`:
   - Job kinds: `specialist_production`, `general_haul`
   - Demand discovery inputs (stations, shrine worshipper slot, resource produced pools)
   - Worker eligibility and conflict rejection
   - Deterministic match ordering (priority, stable ids)
2. **Runtime orchestration** in `TinyfolkJobSchedulingService.server.luau`:
   - Periodic tick (injectable scheduler, same pattern as `PartyMatchmakingQueueService`)
   - Giant-realm-only activation (skip shared hub servers)
   - Apply specialist assignments via `_SpecialistAssignmentService_QueryAPI.AssignForInteraction` (or thin wrapper) with reason `JobScheduled`
   - Track general-haul assignments separately (attributes only; **no** `Hauler` specialist role)
   - `_TinyfolkJobSchedulingService_QueryAPI` debug snapshot seam
   - Optional debug remotes mirroring other labor services
3. **Thin query seams** (minimal additions):
   - Formalize read-only station demand from `StationService` (wrap existing `_StationService_StationState` export)
   - Read resource produced pools from `ResourceFlowState.GetSnapshot()`
   - Shrine worshipper demand for `Shrine_A` (mirror station specialist pattern)
4. **Tests**: pure state spec + runtime entrypoint spec with injected scheduler/players/stations
5. **Docs**: this kickoff + closure/evidence on ship; update `GAME_SPEC.md` labor section when slice ships

### Out of scope / deferred

- NPC / autonomous Tinyfolk entities and movement
- Hauling pathfinding, delivery routing, storage AI (**TIN-32**)
- Final AI polish (**TIN-33**)
- Persistence of scheduled jobs across sessions
- Balance tuning beyond config defaults
- Replacing player `F` interaction flows (scheduler **pre-assigns**; existing activation paths remain authoritative for production ticks)
- New specialist-gated stations beyond current `StationConfig` / shrine catalog

## Architecture

```
[TinyfolkJobSchedulingService tick]
  → collect demands (stations + shrine + produced pools)
  → collect eligible workers (Tinyfolk players)
  → TinyfolkJobSchedulingState.MatchJobs(...)
  → apply specialist assignments (SpecialistAssignmentService)
  → project general-haul job attributes on workers
  → debug snapshot / attributes
```

**Worker model (Slice A):** live `Player` with `Role=Tinyfolk`. Scheduling prepares assignments so players arrive at stations already correctly assigned; movement is still player-driven.

**Exclusive rules enforced:**

| Rule | Enforcement |
|------|-------------|
| One specialist assignment per Tinyfolk | Existing `SpecialistAssignmentService` + scheduler skips workers already assigned to conflicting specialist job |
| One specialist per specialist-gated station slot | Demand marked filled when a worker holds matching `SpecialistAssignedStationId` |
| Hauling is general labor | `general_haul` jobs set haul job attributes only; never assign `Hauler`/`Hauling` specialist labels |
| Hauling does not consume specialist slot | Workers may retain specialist role while holding haul job **only if** config allows; default: one **active scheduled job** per worker (specialist **or** haul, not both) |
| Invalid / conflicting assignments rejected | Pure state returns `rejected` with reason; service logs and skips apply |

## Key files (planned)

| Path | Role |
|------|------|
| `src/ReplicatedStorage/Shared/Config/TinyfolkJobSchedulingConfig.luau` | Tick interval, attributes, job priorities, eligibility flags |
| `src/ReplicatedStorage/Shared/GiantRealm/TinyfolkJobSchedulingState.luau` | Pure demand/match/apply planning |
| `src/ServerScriptService/Services/TinyfolkJobSchedulingService.server.luau` | Tick loop, apply, query API, debug |
| `src/ReplicatedStorage/Shared/Config/SpecialistConfig.luau` | Add `AssignmentReasons.JobScheduled` |
| `src/ServerScriptService/Services/StationService.server.luau` | Add `_StationService_QueryAPI.ListStationDemandSnapshots` (read-only) |
| `tests/tinyfolk_job_scheduling_state.spec.luau` | Pure logic |
| `tests/tinyfolk_job_scheduling_service_runtime_entrypoint.spec.luau` | Service + injected deps |

## Validation

```powershell
.\scripts\run-validation.ps1 -ChangedOnly
lune run tests/tinyfolk_job_scheduling_state.spec.luau
lune run tests/tinyfolk_job_scheduling_service_runtime_entrypoint.spec.luau
lune run tests/specialist_assignment_service_runtime_entrypoint.spec.luau
lune run tests/station_service_runtime_entrypoint.spec.luau
lune run tests/labor_action_state.spec.luau
.\scripts\run-tests.ps1
```

Studio (manual): spawn 2+ Tinyfolk on Giant realm; verify scheduler assigns Woodcutter to `WorkStation_A` when demand exists; verify haul job attribute when produced Wood > 0; verify conflicting double-assign rejected in Output.

## Acceptance criteria mapping

| Criterion | Slice A approach |
|-----------|------------------|
| Tinyfolk assigned valid work in bounded model | Scheduler tick assigns specialist + haul jobs per rules |
| Specialist / general labor rules enforced | Pure state + SpecialistAssignmentService integration |
| Invalid/conflicting assignments rejected | State reasons + no apply on reject |
| Scheduling state visible for debugging | Query API + player attributes + optional debug remote |
| Useful Studio Output logs | `[TinyfolkJobSchedulingService]` structured debug lines |

## Risks

- **Player vs NPC ambiguity:** Slice A schedules **players** only; document clearly to avoid implying villager NPC AI shipped.
- **Double assignment with interaction path:** Scheduler must not fight `ensureInteractionSpecialistAssignment`; prefer assign only when station unfilled and worker unassigned, or idempotent match.
- **Hub vs realm:** Scheduling must no-op on shared hub servers (use existing realm/hub routing helper or `RoleService` realm context).
- **Scope creep into TIN-32:** Do not implement haul movement; haul jobs are labels + demand tracking only.

## Implementation plan (task order)

### Task 1: Config + assignment reason

- Add `TinyfolkJobSchedulingConfig.luau` (tick interval, attribute names, material→source station hints, max jobs per tick).
- Add `SpecialistConfig.AssignmentReasons.JobScheduled`.

### Task 2: Pure scheduling state (TDD)

- Create `TinyfolkJobSchedulingState.luau` with types:
  - `JobDemand` (id, kind, stationId?, specialistRole?, material?, priority)
  - `WorkerSnapshot` (userId, specialistRole, assignedStationId, activeJobKind?, eligible, rejectReason?)
  - `MatchResult` (assignments[], rejections[])
- Implement:
  - `BuildSpecialistDemands(stations, shrineDemand, assignedWorkers)`
  - `BuildHaulDemands(flowSnapshot, assignedHaulWorkers)`
  - `SelectAssignments(demands, workers)` — deterministic sort by `(priority desc, demandId asc, userId asc)`
- Tests in `tinyfolk_job_scheduling_state.spec.luau` covering: happy path assign, station already filled, role mismatch, haul does not set specialist, worker ineligible (non-Tinyfolk), conflict when worker already has job.

### Task 3: Station demand query seam

- Add `_StationService_QueryAPI.ListStationDemandSnapshots()` returning `{ stationId, requiredSpecialistRole, materialType, isActive, activatedByUserId }` from existing registry (no behavior change).

### Task 4: Scheduling service runtime

- Create `TinyfolkJobSchedulingService.server.luau`:
  - Injectable `processScheduler` + `tickIntervalSeconds` (test pattern from `PartyMatchmakingQueueService`)
  - `collectWorkers()` from `Players:GetPlayers()` with eligibility gates (role, alive, not captured — use existing capture/custody attributes)
  - `collectDemands()` via station query + `ResourceFlowState.GetSnapshot()` + static shrine worshipper demand
  - Apply specialist via `_SpecialistAssignmentService_QueryAPI`
  - Set haul attributes from config on worker for `general_haul` matches
  - Clear stale haul attributes when job expires or worker ineligible
  - Export `_TinyfolkJobSchedulingService_QueryAPI.GetDebugSnapshot()`
- Runtime entrypoint spec with mocked players, station demand, flow snapshot, and fake assignment API recording calls.

### Task 5: Audit + docs

- Post-implementation audit per `AGENT_RULES.md`
- Evidence + closure docs; Linear comment on ship
- Update `GAME_SPEC.md` labor section: scheduling slice implemented (bounded), full AI/logistics still future
