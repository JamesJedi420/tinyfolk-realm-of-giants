# TIN-32 Tinyfolk Haul Logistics Evidence (2026-06-19)

## Slice boundary

Proximity-gated haul logistics for **live player Tinyfolk** with TIN-31 `general_haul` scheduled jobs on active Giant realm servers:

- Pure route/phase logic in `TinyfolkHaulLogisticsState`
- Runtime tick in `TinyfolkHaulLogisticsService` (pickup at source, deliver at storage when in range)
- Query seams: `StationService.GetStationHaulSnapshot` / `ApplyScheduledPickup`, `WarehousingService.GetDeliverySnapshot` / `ApplyScheduledDelivery`
- Job clear via `_TinyfolkJobSchedulingService_QueryAPI.ClearScheduledJobForUser`
- No specialist assignment changes; no pathfinding/NPC movement

## Validation commands

```powershell
$bin = "$env:USERPROFILE\.rokit\bin"
& "$bin\lune.exe" run tests/tinyfolk_job_scheduling_state.spec.luau
& "$bin\lune.exe" run tests/tinyfolk_job_scheduling_service_runtime_entrypoint.spec.luau
& "$bin\lune.exe" run tests/tinyfolk_haul_logistics_state.spec.luau
& "$bin\lune.exe" run tests/tinyfolk_haul_logistics_service_runtime_entrypoint.spec.luau
& "$bin\lune.exe" run tests/resource_flow_food.spec.luau
& "$bin\lune.exe" run tests/resource_flow_metal.spec.luau
& "$bin\lune.exe" run tests/station_service_runtime_entrypoint.spec.luau
& "$bin\lune.exe" run tests/warehousing_service_runtime_entrypoint.spec.luau
```

## Results

| Check | Result |
|-------|--------|
| `tinyfolk_haul_logistics_state.spec.luau` | PASS |
| `tinyfolk_haul_logistics_service_runtime_entrypoint.spec.luau` | PASS |
| TIN-31 scheduling specs | PASS |
| Resource flow + station/warehousing regression | PASS |
| StyLua / Selene / luau-lsp changed-only | Run at ship (git PATH required locally) |

## Manual Studio spot-check (deferred)

Let TIN-31 assign haul; walk hauler to source then warehouse/granary; confirm auto-pickup/deliver in Output and `TinyfolkScheduledJobKind` cleared on completion.
