# TIN-101 Food Construction Spend Sink — Closure

**Date:** 2026-06-08  
**Parent:** [TIN-101](https://linear.app/spectranoir/issue/TIN-101)  
**Branch:** `tin-food-construction-spend-sink`

## Goal

Close the food economy loop by spending stored Granary Food on construction sites.

## Shipped

- `ResourceFlowState.SpendStoredAtomic` accepts optional `foodCost`; `AddStoredAtomic` accepts optional `foodAmount` for rollback symmetry.
- `ConstructionConfig.CostBySiteId` includes `food` for `ConstructionSite_A` / `ConstructionSite_B` (4 each).
- `ConstructionService` spends and rolls back food alongside wood/stone; site attributes expose `ConstructionCostFood` and food stored totals.
- E2E regression: `tin_food_construction_spend_runtime_entrypoint.spec.luau` (Farm → Granary → build).

## Validation

```powershell
lune run tests/tin_food_construction_spend_runtime_entrypoint.spec.luau
lune run tests/resource_flow_food.spec.luau
lune run tests/construction_service_runtime_entrypoint.spec.luau
.\scripts\run-validation.ps1 -ChangedOnly
```
