# TIN-255 Control-Dominant Scheduling Deprioritize Kickoff (2026-06-20)

## Issue

- ID: TIN-255
- Title: Deprioritize control-dominant Tinyfolk in job scheduling worker order
- Linear: https://linear.app/spectranoir/issue/TIN-255/deprioritize-control-dominant-tinyfolk-in-job-scheduling-worker-order
- Milestone: Progression, Economy, and Loadouts
- Related: [TIN-254](https://linear.app/spectranoir/issue/TIN-254), [TIN-28](https://linear.app/spectranoir/issue/TIN-28), [TIN-31](https://linear.app/spectranoir/issue/TIN-31), [TIN-251](https://linear.app/spectranoir/issue/TIN-251)

## Goal

When multiple eligible Tinyfolk compete for the same scheduled job demand, deprioritize control-dominant dyadic workers so balanced and favor-dominant workers win even when raw favor is slightly lower.

## Context

TIN-254 ranks workers by raw dyadic favor (desc), control (asc), userId (asc). A control-dominant Tinyfolk with slightly higher raw favor can still win over a balanced worker. Inspect maps control-dominant dyads to warning tone via `SocialEconomyState.ResolveDominantAxis`; scheduling should mirror that axis semantics.

## Slice boundary

### In scope

1. `ResolveWorkerDominantAxis(worker)` — `SocialEconomyState.ResolveDominantAxis` on resolved favor/control
2. Sort comparator when dyadic ranking enabled:
   - Tier 1: dominance order favor > balanced > control
   - Tier 2: favor desc
   - Tier 3: control asc
   - Tier 4: userId asc
3. `DeprioritizeControlDominantWorkers = true` in `TinyfolkJobSchedulingConfig`
4. `scheduleDominantAxis` in `FormatWorkerForDebug`
5. Pure tests + `SYSTEM_BOUNDARIES.md` update
6. Studio evidence doc (PENDING rows)

### Out of scope

- Service changes (TIN-254 snapshot wiring sufficient)
- Labor yield / intimidation math changes
- Per-Tinyfolk morale simulation
- Pathfinding, NPC haulers, persistence

## Validation

```powershell
lune run tests/tinyfolk_job_scheduling_state.spec.luau
.\scripts\run-validation.ps1 -ChangedOnly
```

## Session workflow

1. TIN-255 → **In Progress** in Linear
2. Branch: `tin-255-control-dominant-scheduling-deprioritize` from `master`
3. Implement shared → config → tests → audit → ship loop

## Deferred follow-ups

- Per-Tinyfolk morale simulation
- Giant HUD polish (TIN-252 deferred)
