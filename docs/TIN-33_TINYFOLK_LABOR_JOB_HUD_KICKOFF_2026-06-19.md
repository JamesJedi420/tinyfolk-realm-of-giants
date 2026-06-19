# TIN-33 Tinyfolk Labor Job HUD Kickoff (2026-06-19)

## Issue

- ID: TIN-33
- Title: Implement final AI polish
- Linear: https://linear.app/spectranoir/issue/TIN-33/implement-final-ai-polish

## Goal

Client presentation for TIN-31 scheduled jobs and TIN-32 haul logistics: screen HUD + lightweight world billboards on route targets. Read-only; no pathfinding or server logic changes.

## Slice boundary

### In scope

1. `TinyfolkLaborJobHudPresentation` — pure HUD model from scheduling + haul attributes
2. `TinyfolkLaborJobHudClient` — screen panel + billboard on active target part
3. `TinyfolkLaborJobHudConfig` — display strings and layout constants
4. Tests: `tinyfolk_labor_job_hud_presentation.spec.luau`
5. Docs + `GAME_SPEC.md` labor section update

### Out of scope

- NPC movement, navmesh, server scheduling/logistics changes
- InteractionResolver redesign, persistence, balance tuning

## Validation

```powershell
lune run tests/tinyfolk_labor_job_hud_presentation.spec.luau
lune run tests/tinyfolk_job_scheduling_state.spec.luau
lune run tests/tinyfolk_haul_logistics_state.spec.luau
.\scripts\run-validation.ps1 -ChangedOnly
```

## Acceptance criteria (narrowed)

| Criterion | Approach |
|-----------|----------|
| Scheduled jobs readable in play | Screen HUD + billboards |
| Consistent state transitions | Driven by existing server attrs |
| Debug observable | Client debug logs on transitions |
