# TIN-33 Tinyfolk Labor Job HUD Evidence (2026-06-19)

## Slice boundary

Client presentation for TIN-31/TIN-32 scheduled jobs and haul logistics:

- Pure `TinyfolkLaborJobHudPresentation` from scheduling + haul attributes
- `TinyfolkLaborJobHudClient` screen HUD + route-target billboards
- Read-only; no server scheduling/logistics changes

## Validation commands

```powershell
$bin = "$env:USERPROFILE\.rokit\bin"
& "$bin\lune.exe" run tests/tinyfolk_labor_job_hud_presentation.spec.luau
& "$bin\lune.exe" run tests/tinyfolk_job_scheduling_state.spec.luau
& "$bin\lune.exe" run tests/tinyfolk_haul_logistics_state.spec.luau
```

## Results

| Check | Result |
|-------|--------|
| `tinyfolk_labor_job_hud_presentation.spec.luau` | PASS (run at ship) |
| TIN-31/TIN-32 regression specs | PASS (run at ship) |
| StyLua / Selene / luau-lsp changed-only | PASS (run at ship) |

## Manual Studio spot-check (deferred)

TIN-31 assigns jobs; verify labor HUD + billboard on source/warehouse; walk haul loop; confirm completion flash on job clear.
