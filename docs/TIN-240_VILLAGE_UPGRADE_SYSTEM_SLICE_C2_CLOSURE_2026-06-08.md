# TIN-240 Slice C2 Closure — Village Upgrade Hub + Board Deprecation Hygiene

**Date:** 2026-06-08  
**Issue:** [TIN-240](https://linear.app/spectranoir/issue/TIN-240)  
**Branch:** `tin-240-c2-closure-hygiene`

## Shipped slices (prior PRs)

| Slice | PR | Summary |
|-------|-----|---------|
| C2a | #17 | Read-only upgrade hub at `GiantUpgradeBoard_A` |
| C2b | #18 | Deprecate board purchases; re-home Giant effects to Shrine / Giant Dwelling levels |

## Closure hygiene (this slice)

- Removed `UpgradeBoardTest.client.luau` (legacy purchase smoke script).
- Slimmed `UpgradeBoardClient` to debug-only keys (`P` = effect debug, `L` = essence drain); no purchase remotes.
- `UpgradeBoardService` clears legacy `GiantUpgrade_*` session attributes on setup/reset; progression status is `Deprecated`.
- Debug payloads report `shrineLevel` / `dwellingLevel` instead of session purchase CSV.
- `VillageUpgradeHubClient` re-requests hub snapshot when a worksite upgrade succeeds while the hub panel is open.
- Added read-only `GiantEffectHudClient` projecting `GiantEffect_*` attributes for Giants.

## Deferred

- **C2c** `PowerBudgetProduction` — separate generation contract; requires explicit design sign-off.

## Giant essence scope

`GiantEssenceSession` remains for shrine tribute and other bounded session spend paths. Board buff purchases are not a valid spend reason after C2b.

## Validation

```powershell
lune run tests/giant_effect_hud_presentation.spec.luau
lune run tests/tin_240_giant_effect_hub_runtime_entrypoint.spec.luau
lune run tests/village_upgrade_hub_state.spec.luau
.\scripts\run-validation.ps1 -ChangedOnly
.\scripts\run-tests.ps1
```

Studio: F at board → hub; upgrade Shrine/dwelling with hub open → lines refresh; Giant HUD shows updated `GiantEffect_*` values; `P` debug shows worksite levels not purchase CSV.
