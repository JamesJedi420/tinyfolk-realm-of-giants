# TIN-255 Control-Dominant Scheduling Deprioritize — Closure

**Date:** 2026-06-20  
**Issue:** [TIN-255](https://linear.app/spectranoir/issue/TIN-255/deprioritize-control-dominant-tinyfolk-in-job-scheduling-worker-order)

## Shipped

- `ResolveWorkerDominantAxis` — delegates to `SocialEconomyState.ResolveDominantAxis` on resolved schedule rank.
- Dominance-tier sort when `DeprioritizeControlDominantWorkers` is true: favor > balanced > control, then favor desc, control asc, userId asc.
- `DeprioritizeControlDominantWorkers` config kill-switch in `TinyfolkJobSchedulingConfig`.
- `scheduleDominantAxis` in `FormatWorkerForDebug`.
- Tests extended in `tests/tinyfolk_job_scheduling_state.spec.luau`.
- `docs/SYSTEM_BOUNDARIES.md` updated.

## Validation (automated)

```powershell
lune run tests/tinyfolk_job_scheduling_state.spec.luau
.\scripts\run-validation.ps1 -ChangedOnly
```

## Studio smoke

**Status: PENDING** — tracked in [TIN-255 Studio evidence](TIN-255_CONTROL_DOMINANT_SCHEDULING_DEPRIORITIZE_STUDIO_EVIDENCE_2026-06-20.md).

## Deferred

- Per-Tinyfolk morale simulation
- Giant HUD polish (TIN-252 deferred)
