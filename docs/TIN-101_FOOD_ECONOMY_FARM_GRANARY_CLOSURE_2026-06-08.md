# TIN-101 Food Economy E2E — Farm_A → Granary_A Closure

**Date:** 2026-06-08  
**Parent:** [TIN-101](https://linear.app/spectranoir/issue/TIN-101) village upgrade system / production economy  
**Branch:** `tin-food-economy-farm-granary-e2e`

## Goal

Harden the full Food production loop: **Farm_A produce → haul → Granary_A store**, with regression coverage and doc alignment.

## Shipped

- **Haul labor fix:** `StationService` allows any in-range Tinyfolk to haul produced Food (and Wood/Stone) without consuming the specialist assignment slot; Farmer remains required to activate production.
- **Observability:** station debug snapshots include Food flow fields; warehousing debug includes Food totals.
- **Regression:** `tin_food_economy_farm_granary_runtime_entrypoint.spec.luau` exercises produce → haul (general labor) → granary deliver end-to-end.
- **Docs:** `GAME_SPEC.md` and `AGENT_RULES.md` updated — Granary is live for Food, not deferred.

## Flow contract

| Step | Actor | Surface | Effect |
|------|-------|---------|--------|
| Produce | Farmer @ Farm_A | F activate | `Food` produced pool increases |
| Haul | Any Tinyfolk @ Farm_A | F pickup | produced → in-transit |
| Store | Any Tinyfolk @ Granary_A | F deliver | in-transit → stored (`Granary_A`) |

## Validation

```powershell
lune run tests/tin_food_economy_farm_granary_runtime_entrypoint.spec.luau
lune run tests/resource_flow_food.spec.luau
lune run tests/station_service_runtime_entrypoint.spec.luau
lune run tests/warehousing_service_runtime_entrypoint.spec.luau
.\scripts\run-validation.ps1 -ChangedOnly
```

Studio: assign Farmer → activate Farm_A → wait for ticks → any Tinyfolk F at farm (pickup) → F at Granary_A (deliver) → `FoodStoredTotal` increases on granary.
