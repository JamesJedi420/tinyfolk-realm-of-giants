# TIN-254 Dyadic Job Scheduling Worker Rank Kickoff (2026-06-20)

## Issue

- ID: TIN-254
- Title: Prefer dyadic-favor Tinyfolk in job scheduling worker order
- Linear: https://linear.app/spectranoir/issue/TIN-254/prefer-dyadic-favor-tinyfolk-in-job-scheduling-worker-order
- Milestone: Progression, Economy, and Loadouts
- Related: [TIN-31](https://linear.app/spectranoir/issue/TIN-31/implement-tinyfolk-ai-job-scheduling), [TIN-251](https://linear.app/spectranoir/issue/TIN-251/project-dyadic-loyalty-to-tinyfolk-inspect), [TIN-28](https://linear.app/spectranoir/issue/TIN-28/implement-social-economy-layer), [TIN-253](https://linear.app/spectranoir/issue/TIN-253/loyalty-tone-inspect-selection-highlight)

## Goal

When multiple eligible Tinyfolk compete for the same scheduled job demand, prefer workers with higher projected dyadic favor instead of arbitrary `userId` ordering.

## Context

TIN-31 ships `TinyfolkJobSchedulingState.SelectAssignments`, which sorts workers by ascending `userId` and picks the first eligible worker per demand. TIN-251 projects `SocialDyadicFavor` / `SocialDyadicControl` onto in-realm Tinyfolk players from `SocialEconomyState.dyadicByUserId`, but scheduling does not read those attrs today.

Labor yield already resolves target-aware compliance via `LaborComplianceState.ResolveFavorComplianceBonus` and `GetEffectSnapshot(targetUserId)`. This slice closes the scheduling gap only — assignment priority, not yield math.

## Slice boundary

### In scope

1. Extend `WorkerSnapshot` with optional `dyadicFavor` / `dyadicControl` (0–100)
2. `TinyfolkJobSchedulingState.ResolveWorkerScheduleRank` (or equivalent pure helper):
   - Primary: favor descending
   - Tie-break: control ascending (favor-dominant workers preferred)
   - Missing attrs → `SocialEconomyConfig.DefaultFavor` / `DefaultControl` (50)
   - Final tie-break: `userId` ascending (deterministic)
3. Update `sortWorkers` to use schedule rank
4. `TinyfolkJobSchedulingService.buildWorkerSnapshot` reads projected dyadic attrs; remove redundant pre-sort in `collectWorkerSnapshots`
5. Optional kill-switch in `TinyfolkJobSchedulingConfig` (`UseDyadicWorkerRanking = true`)
6. Pure tests in `tests/tinyfolk_job_scheduling_state.spec.luau`
7. `docs/SYSTEM_BOUNDARIES.md` note under TIN-28 consumers and TIN-31 scheduling
8. Studio evidence doc (PENDING rows)

### Out of scope

- Control-dominant penalty or intimidation deprioritization
- Haul pathfinding / delivery routing (TIN-32)
- NPC entities, persistence of scheduled jobs, new specialist roles
- Changes to `LaborComplianceState` yield formulas
- Per-Tinyfolk morale simulation

## Architecture

```
[TinyfolkJobSchedulingService tick]
  → buildWorkerSnapshot (reads SocialDyadicFavor / SocialDyadicControl)
  → TinyfolkJobSchedulingState.SelectAssignments
      → sortWorkers by ResolveWorkerScheduleRank
      → first eligible worker per demand wins
```

## Key files

| Path | Purpose |
|------|---------|
| `src/ReplicatedStorage/Shared/GiantRealm/TinyfolkJobSchedulingState.luau` | Worker rank + sort |
| `src/ReplicatedStorage/Shared/Config/TinyfolkJobSchedulingConfig.luau` | Optional ranking flag |
| `src/ReplicatedStorage/Shared/Config/SocialEconomyConfig.luau` | Attr names + defaults |
| `src/ServerScriptService/Services/TinyfolkJobSchedulingService.server.luau` | Snapshot wiring |
| `tests/tinyfolk_job_scheduling_state.spec.luau` | Ranking cases |
| `docs/SYSTEM_BOUNDARIES.md` | Consumer note |

## Validation

```powershell
lune run tests/tinyfolk_job_scheduling_state.spec.luau
.\scripts\run-validation.ps1 -ChangedOnly
.\scripts\run-tests.ps1
```

Studio (evidence doc):

- Two Tinyfolk with different dyadic favor, one open station demand → higher-favor worker scheduled first
- Equal favor → lower control wins; equal both → stable userId tie-break

## Acceptance criteria

- Two equally eligible workers, one demand → higher dyadic favor wins
- Equal favor → lower control preferred; equal both → deterministic userId tie-break
- Missing dyadic attrs → neutral defaults with userId tie-break
- Existing scheduling specs green; new ranking cases added
- Debug snapshot exposes worker rank inputs where applicable

## Session workflow

1. TIN-254 → **In Progress** in Linear
2. Branch: `tin-254-dyadic-job-scheduling-worker-rank` from `master`
3. Implement shared → service → tests → audit → ship loop

## Deferred follow-ups

- Control-dominant scheduling penalties or intimidation-aware deprioritization
- Per-Tinyfolk morale simulation
- Haul logistics AI (TIN-32)
