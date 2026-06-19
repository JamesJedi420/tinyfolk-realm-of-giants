# TIN-39 Advanced Construction Material Spend Kickoff (2026-06-19)

## Issue

- ID: TIN-39
- Title: Implement advanced construction and material spending behavior
- Milestone: Progression, Economy, and Loadouts
- Linear: https://linear.app/spectranoir/issue/TIN-39/implement-advanced-construction-and-material-spending-behavior

## Goal

Expand construction spending beyond the minimal Wood/Stone/Food prototype: centralized cost parsing/affordability in shared logic, **Metal** as a fourth stored spend material, and debug surfaces for richer material combinations.

## Problem (current gap)

- `ConstructionService` parses costs inline (`getSiteCost`) with no shared validation seam.
- `ResourceFlowState.SpendStoredAtomic` supports Wood/Stone/Food only; Metal stored totals cannot fund construction (TIN-27 deferred note).
- `ConstructionSite_C` exists on the map but has no cost config and is not registered.
- District build costs carry Wood/Stone only.

## Slice A boundary (this session)

### In scope

1. **Pure spend logic** — `Shared/Construction/ConstructionSpendState.luau`:
   - Normalize config cost entries (wood, stone, food, metal)
   - Resolve site and district costs
   - Affordability checks against flow stored snapshots
2. **Resource flow** — optional `metalCost` on `SpendStoredAtomic` / `AddStoredAtomic` (rollback symmetry)
3. **Config** — `ConstructionSite_C` metal-requiring site; district default food/metal fields (default 0)
4. **ConstructionService** — use shared spend state; metal debug attributes; district food/metal spend
5. **Tests** — `construction_spend_state.spec.luau`; metal construction runtime assertions; resource flow metal spend regression
6. **Docs** — this kickoff; `GAME_SPEC.md` construction spend line

### Out of scope

- Multi-stage / partial build progression
- Per-district cost override tables beyond defaults
- Persistence, UX polish, ledger-path unification with `GiantBuildModeService`
- District range checks

## Architecture

```
ConstructionConfig (CostBySiteId, DistrictDefaultCost)
  → ConstructionSpendState.ResolveSiteCost / ResolveDistrictCost
  → ConstructionSpendState.ValidateAffordability(flow snapshot)
  → ResourceFlowState.SpendStoredAtomic(..., food, metal)
  → ConstructionService build mutation + debug attributes
```

## Validation

```powershell
lune run tests/construction_spend_state.spec.luau
lune run tests/construction_service_runtime_entrypoint.spec.luau
lune run tests/tin_food_construction_spend_runtime_entrypoint.spec.luau
lune run tests/resource_flow_metal.spec.luau
.\scripts\run-validation.ps1 -ChangedOnly
```

## Acceptance criteria mapping (Slice A)

| Criterion | Approach |
|-----------|----------|
| Richer material combinations | Four-material cost model + `ConstructionSite_C` |
| Advanced spend rules | Shared normalize/affordability; metal stored spend |
| Debug state exposed | Metal cost + stored attributes on sites; debug remote fields |
| Testable | Pure state spec + construction runtime metal path |
