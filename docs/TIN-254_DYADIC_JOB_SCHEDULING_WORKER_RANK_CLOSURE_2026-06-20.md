# TIN-254 Dyadic Job Scheduling Worker Rank — Closure

**Date:** 2026-06-20  
**Issue:** [TIN-254](https://linear.app/spectranoir/issue/TIN-254/prefer-dyadic-favor-tinyfolk-in-job-scheduling-worker-order)

## Shipped

- `WorkerSnapshot` extended with optional `dyadicFavor` / `dyadicControl`.
- `TinyfolkJobSchedulingState.ResolveWorkerScheduleRank` — favor desc, control asc tie-break, userId asc final tie-break; missing attrs default to `SocialEconomyConfig` (50/50).
- `sortWorkers` uses dyadic rank when `TinyfolkJobSchedulingConfig.UseDyadicWorkerRanking` is true.
- `TinyfolkJobSchedulingService.buildWorkerSnapshot` reads projected `SocialDyadicFavor` / `SocialDyadicControl`; service pre-sort removed.
- `FormatWorkerForDebug` exposes resolved schedule rank in debug snapshots.
- Tests extended in `tests/tinyfolk_job_scheduling_state.spec.luau`.
- `docs/SYSTEM_BOUNDARIES.md` updated.

## Validation (automated)

```powershell
lune run tests/tinyfolk_job_scheduling_state.spec.luau
.\scripts\run-validation.ps1 -ChangedOnly
```

## Studio smoke

**Status: PENDING** — tracked in [TIN-254 Studio evidence](TIN-254_DYADIC_JOB_SCHEDULING_WORKER_RANK_STUDIO_EVIDENCE_2026-06-20.md).

## Deferred

- Control-dominant scheduling penalties or intimidation-aware deprioritization
- Per-Tinyfolk morale simulation
- Haul logistics AI (TIN-32)
