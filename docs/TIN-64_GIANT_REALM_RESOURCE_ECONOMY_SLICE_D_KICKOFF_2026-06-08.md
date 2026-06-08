# TIN-64 Giant Realm Resource Economy Slice D Kickoff (2026-06-08)

## Issue
- ID: TIN-64
- Title: Implement Giant realm resource economy
- Linear: https://linear.app/spectranoir/issue/TIN-64/implement-giant-realm-resource-economy

## Slice D boundary (village upgrade ledger spend follow-up)
- Centralize worksite upgrade spending in `GiantBuildModeService.SpendWorksiteUpgradeCost`.
- Prefer persistent ledger Wood/Stone/Essence when affordable; fall back to session stored Wood/Stone (Essence remains ledger-only).
- Log session/mixed spends through `EventLogService` (`realm_resource_spend`).
- Roll back ledger/session portions via `RollbackWorksiteUpgradeSpend`.
- Route `VillageWorksiteUpgradeService` through the build-mode spend API (with `_G` query fallback for tests).

## Key files
- `src/ServerScriptService/Services/GiantBuildModeService.server.luau`
- `src/ServerScriptService/Services/VillageWorksiteUpgradeService.server.luau`
- `src/ReplicatedStorage/Shared/GiantRealm/GiantRealmResourceState.luau` (`worksite_upgrade` spend kind)

## Validation
```powershell
lune run tests/giant_realm_resource_state.spec.luau
lune run tests/giant_build_mode_service_runtime_entrypoint.spec.luau
lune run tests/village_worksite_upgrade_service_runtime_entrypoint.spec.luau
.\scripts\run-validation.ps1 -ChangedOnly
.\scripts\run-tests.ps1
```

## Issue closure
If this slice ships with prior TIN-64 slices (A–C), the TIN-64 acceptance criteria should be satisfied and the issue can move to **Done**.
