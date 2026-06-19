# TIN-39 Advanced Construction Material Spend Evidence (2026-06-19)

## Slice boundary (Slice A)

Four-material construction spend with shared affordability logic:

- `ConstructionSpendState` — normalize/resolve site and district costs; affordability checks
- `ResourceFlowState.SpendStoredAtomic` / `AddStoredAtomic` — optional metal spend/rollback
- `ConstructionConfig` — `ConstructionSite_C` (wood/stone/metal); district default food/metal fields
- `ConstructionService` — shared spend helpers; metal debug attributes; district food/metal spend
- `GAME_SPEC.md` — construction can spend stored Metal from Warehouse

## Out of scope (deferred)

- Multi-stage / partial build progression
- Per-district cost override tables
- Persistence, UX polish, GiantBuildMode ledger unification
- Full farm→granary labor E2E in `tin_food` construction test (TIN-37 labor-action gates)

## Validation commands

```powershell
lune run tests/construction_spend_state.spec.luau
lune run tests/construction_service_runtime_entrypoint.spec.luau
lune run tests/tin_food_construction_spend_runtime_entrypoint.spec.luau
lune run tests/resource_flow_metal.spec.luau
.\scripts\run-validation.ps1 -ChangedOnly
```

## Results

| Check | Result |
|-------|--------|
| `construction_spend_state.spec.luau` | PASS |
| `construction_service_runtime_entrypoint.spec.luau` | PASS (metal site build path) |
| `tin_food_construction_spend_runtime_entrypoint.spec.luau` | PASS |
| `resource_flow_metal.spec.luau` | PASS |
| StyLua / Selene / luau-lsp changed-only | PASS |

## Manual Studio spot-check (deferred)

Stock Warehouse metal, start `ConstructionSite_C` build; confirm metal stored totals decrement and site debug attributes reflect four-material cost.
