# TIN-101 Food Worksite Upgrade Spend — Closure

**Date:** 2026-06-08  
**Parent:** [TIN-101](https://linear.app/spectranoir/issue/TIN-101)  
**Branch:** `tin-101-worksite-upgrade-food-spend`

## Goal

Spend stored Granary Food when upgrading food-adjacent worksites (Farm, Granary, Pen).

## Shipped

- `VillageWorksiteUpgradeConfig` — `food` cost on Farm / Granary / Pen levels 1–3 (2 / 4 / 6).
- `VillageWorksiteUpgradeState.ResolveUpgradeCost` and upgrade transitions include `food`.
- `GiantBuildModeService.SpendWorksiteUpgradeCost` / `RollbackWorksiteUpgradeSpend` debit and restore stored Food via `ResourceFlowState`.
- `VillageWorksiteUpgradeService` forwards food through spend/rollback; presentation shows `F` in cost summary.

## Validation

```powershell
lune run tests/village_worksite_upgrade_state.spec.luau
lune run tests/village_worksite_upgrade_presentation.spec.luau
lune run tests/village_worksite_upgrade_service_runtime_entrypoint.spec.luau
lune run tests/giant_build_mode_service_runtime_entrypoint.spec.luau
.\scripts\run-validation.ps1 -ChangedOnly
```
