# TIN-31 Tinyfolk AI Job Scheduling Evidence (2026-06-19)

## Slice boundary

Server-owned bounded job scheduling for **live player Tinyfolk** on active Giant realm servers:

- Job kinds: `specialist_production`, `general_haul`
- Specialist apply via `_SpecialistAssignmentService_QueryAPI.AssignForJobScheduling` (`JobScheduled` reason)
- Haul jobs via `TinyfolkScheduledJob*` player attributes only (no haul specialist role, no movement AI)
- Hub / inactive realm no-op via `_RoleService_QueryAPI.GetActiveGiantRealmOwnerUserId`

## Validation commands

```powershell
$bin = "$env:USERPROFILE\.rokit\bin"
& "$bin\lune.exe" run tests/tinyfolk_job_scheduling_state.spec.luau
& "$bin\lune.exe" run tests/tinyfolk_job_scheduling_service_runtime_entrypoint.spec.luau
& "$bin\lune.exe" run tests/specialist_assignment_service_runtime_entrypoint.spec.luau
& "$bin\lune.exe" run tests/station_service_runtime_entrypoint.spec.luau
.\scripts\run-validation.ps1 -ChangedOnly
```

## Results

| Check | Result |
|-------|--------|
| `tinyfolk_job_scheduling_state.spec.luau` | PASS |
| `tinyfolk_job_scheduling_service_runtime_entrypoint.spec.luau` | PASS |
| Specialist / station regression specs | PASS (run at ship) |
| StyLua / Selene / luau-lsp changed-only | PASS (run at ship) |

## Manual Studio spot-check (deferred)

Spawn 2+ Tinyfolk on Giant realm; confirm Woodcutter pre-assign to `WorkStation_A`, haul attribute when Wood produced > 0, no duplicate assign on second tick.
