# TIN-101 Village Upgrade System Slice A Kickoff (2026-06-08)

## Issue
- ID: TIN-101
- Title: Implement village upgrade system
- Linear: https://linear.app/spectranoir/issue/TIN-101/implement-village-upgrade-system

## Slice A boundary
- Add bounded worksite upgrade levels for `WorkStation_*` and `MiningStation_*`.
- Upgrades cost persistent realm ledger resources via `GiantBuildModeService.ApplyResourceSpend`.
- Upgrades modify station production per-tick amount and produced capacity caps.
- Persist upgrade state on Giant realm save root (`worksiteUpgrades`).
- Giant-only upgrade requests through `VillageWorksiteUpgradeRequest`.

## Deferred (Slice B+)
- Farms, pens, guard towers, Giant dwellings, shrine/warehouse/granary capacity upgrades.
- Client upgrade board UX beyond existing interaction surfaces.
- Session-pool fallback spending for upgrades.

## Key files
- `src/ReplicatedStorage/Shared/Config/VillageWorksiteUpgradeConfig.luau`
- `src/ReplicatedStorage/Shared/GiantRealm/VillageWorksiteUpgradeState.luau`
- `src/ServerScriptService/Services/VillageWorksiteUpgradeService.server.luau`
- `src/ReplicatedStorage/Shared/GiantRealm/GiantRealmSaveSchema.luau`
- `src/ServerScriptService/Services/StationService.server.luau`

## Validation
```powershell
lune run tests/village_worksite_upgrade_state.spec.luau
lune run tests/giant_realm_save_schema.spec.luau
lune run tests/giant_build_mode_service_runtime_entrypoint.spec.luau
.\scripts\run-validation.ps1 -ChangedOnly
```
