# TIN-64 Giant Realm Resource Economy Slice B Kickoff (2026-06-08)

## Issue
- ID: TIN-64
- Title: Implement Giant realm resource economy
- Linear: https://linear.app/spectranoir/issue/TIN-64/implement-giant-realm-resource-economy

## Slice B boundary
- Add award producers:
  - `shrine_tribute_tick` via `ShrineService` (50% of generated Essence credited to persistent ledger)
  - `rescue_contract_defense_failure` via `RescueContractService` on successful rescue completion
- Add persistent ledger spending for structure placement (`structure_placement` spend kind).
- Prefer persistent ledger Wood/Stone when affordable; fall back to session stored totals.
- Log spends through `EventLogService` (`realm_resource_spend`).

## Deferred (Slice C+)
- Client treasury HUD.
- Cross-server durable pair-history store.
- Village upgrade spending beyond structure placement.
- Defended raid producer (no bounded raid award hook yet).

## Key files
- `src/ReplicatedStorage/Shared/GiantRealm/GiantRealmResourceState.luau`
- `src/ReplicatedStorage/Shared/GiantRealm/GiantRealmSaveSchema.luau`
- `src/ServerScriptService/Services/GiantBuildModeService.server.luau`
- `src/ServerScriptService/Services/ShrineService.server.luau`
- `src/ServerScriptService/Services/RescueContractService.server.luau`

## Validation
```powershell
lune run tests/giant_realm_resource_state.spec.luau
lune run tests/giant_realm_resource_resolver.spec.luau
lune run tests/giant_realm_save_schema.spec.luau
lune run tests/rescue_contract_service_runtime_entrypoint.spec.luau
.\scripts\run-validation.ps1 -ChangedOnly
```
