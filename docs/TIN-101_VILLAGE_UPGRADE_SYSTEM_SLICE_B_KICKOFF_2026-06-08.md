# TIN-101 Village Upgrade System Slice B Kickoff (2026-06-08)

## Issue
- ID: TIN-101
- Title: Implement village upgrade system
- Linear: https://linear.app/spectranoir/issue/TIN-101/implement-village-upgrade-system

## Slice B boundary
- Extend upgrade kinds to **Warehouse**, **Granary**, and **Shrine** with capacity modifiers (in-transit haul caps, shrine essence cap).
- Wire capacity modifiers into `ResourceFlowState` and `ShrineService`.
- Add Giant **F-key interaction** for worksite upgrades via `InteractionResolver` → `VillageWorksiteUpgradeRequest`.
- Add client upgrade feedback HUD (`GiantWorksiteUpgradeFeedbackClient`).

## Deferred (Slice C+)
- Farms, pens, guard towers, Giant dwellings (no authored map contracts yet).
- Upgrade board UX overhaul beyond existing board flow.

## Key files
- `src/ReplicatedStorage/Shared/Config/VillageWorksiteUpgradeConfig.luau`
- `src/ReplicatedStorage/Shared/GiantRealm/VillageWorksiteUpgradeState.luau`
- `src/ReplicatedStorage/Shared/GiantRealm/VillageWorksiteUpgradePresentation.luau`
- `src/ServerScriptService/Services/VillageWorksiteUpgradeService.server.luau`
- `src/ServerScriptService/Services/ResourceFlowState.luau`
- `src/ServerScriptService/Services/ShrineService.server.luau`
- `src/StarterPlayer/StarterPlayerScripts/Client/InteractionResolver.client.luau`
- `src/StarterPlayer/StarterPlayerScripts/Client/GiantWorksiteUpgradeFeedbackClient.client.luau`

## Validation
```powershell
lune run tests/village_worksite_upgrade_state.spec.luau
lune run tests/village_worksite_upgrade_presentation.spec.luau
lune run tests/village_worksite_upgrade_service_runtime_entrypoint.spec.luau
.\scripts\run-validation.ps1 -ChangedOnly
.\scripts\run-tests.ps1
```
