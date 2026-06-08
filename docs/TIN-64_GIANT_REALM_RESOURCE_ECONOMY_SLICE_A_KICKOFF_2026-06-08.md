# TIN-64 Giant Realm Resource Economy Slice A Kickoff (2026-06-08)

## Issue
- ID: TIN-64
- Title: Implement Giant realm resource economy
- Linear: https://linear.app/spectranoir/issue/TIN-64/implement-giant-realm-resource-economy

## Slice A boundary
- Add persistent Giant realm resource ledger (`Essence`, `Wood`, `Stone`) on Giant realm save root.
- Award from bounded gameplay producers only:
  - `containment_custody_end` via `ContainmentRewardResolver`
  - `defense_escape_outcome` via `GiantBuildModeService.RecordEscapeDefenseOutcome`
- Enforce pair anti-farming depreciation in `GiantRealmResourceResolver`.
- Log resource awards through `EventLogService`.
- Keep session Wood/Stone/Essence pools separate from persistent realm ledger totals.

## Deferred (Slice B+)
- Tribute structures, contracts beyond rescue failure awards, client treasury HUD.
- Cross-server durable pair-history store.
- Spending persistent realm resources on construction/upgrades.

## Key files
- `src/ReplicatedStorage/Shared/GiantRealm/GiantRealmResourceState.luau`
- `src/ReplicatedStorage/Shared/GiantRealm/GiantRealmSaveSchema.luau`
- `src/ServerScriptService/Services/GiantRealmResourceResolver.luau`
- `src/ServerScriptService/Services/GiantBuildModeService.server.luau`
- `src/ServerScriptService/Services/ContainmentRewardResolver.luau`

## Validation
```powershell
lune run tests/giant_realm_resource_state.spec.luau
lune run tests/giant_realm_resource_resolver.spec.luau
lune run tests/giant_realm_save_schema.spec.luau
lune run tests/containment_reward_resolver.spec.luau
.\scripts\run-validation.ps1 -ChangedOnly
```
