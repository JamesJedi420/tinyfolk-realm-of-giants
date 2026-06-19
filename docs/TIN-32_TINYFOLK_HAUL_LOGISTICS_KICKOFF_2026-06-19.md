# TIN-32 Tinyfolk Haul Logistics Kickoff (2026-06-19)

## Issue

- ID: TIN-32
- Title: Implement AI logistics behavior
- Milestone: Progression, Economy, and Loadouts
- Linear: https://linear.app/spectranoir/issue/TIN-32/implement-ai-logistics-behavior

## Goal

Execute bounded proximity-gated haul logistics for **live player Tinyfolk** with TIN-31 `general_haul` scheduled jobs. Players still walk to source and storage; the server auto-pickups and auto-delivers when in `ActivationRangeStuds`. No NPC pathfinding, no specialist-slot changes.

## Problem (current gap)

- TIN-31 assigns `TinyfolkScheduledJob*` haul attributes but does not move resources.
- Manual `F` haul hold still requires player interaction at stations and warehouses.
- Scheduled haul workers remain job-locked until logistics completes and clears the assignment.

## Slice boundary

### In scope

1. **Pure logistics logic** in `Shared/GiantRealm/TinyfolkHaulLogisticsState.luau`:
   - Route resolution (source station → delivery point by material)
   - Phase machine (`pickup` / `deliver`)
   - Eligibility, range, manual-haul deferral, completion detection
2. **Runtime orchestration** in `TinyfolkHaulLogisticsService.server.luau`:
   - Giant-realm-only tick (injectable scheduler, TIN-31 pattern)
   - Consume `TinyfolkScheduledJobKind=general_haul`
   - Pickup via `ResourceFlowState.TransferProducedToInTransit`
   - Deliver via `_WarehousingService_QueryAPI.ApplyScheduledDelivery`
   - Clear job via `_TinyfolkJobSchedulingService_QueryAPI.ClearScheduledJobForUser`
   - Debug attributes + query API + optional debug remote
3. **Thin query seams:**
   - `StationService`: `GetStationHaulSnapshot(stationId)`
   - `WarehousingService`: `GetDeliverySnapshot(material)`, `ApplyScheduledDelivery`
4. **Tests:** pure state spec + runtime entrypoint spec; TIN-31 regression
5. **Docs:** this kickoff + evidence/closure; update `GAME_SPEC.md` labor section

### Out of scope

- NPC entities, Humanoid pathfinding, client navigation polish (TIN-33)
- Persistence of logistics state
- Replacing manual haul hold (coexist; defer when `HaulInteractionActive` or haul cooldown)
- Specialist scheduling or assignment changes

## Architecture

```
[TinyfolkHaulLogisticsService tick]
  → players with TinyfolkScheduledJobKind=general_haul
  → ResolveRoute(material, sourceStationId)
  → phase from flow snapshot
  → in range at target → transfer
  → on complete → ClearScheduledJobForUser
```

## Validation

```powershell
lune run tests/tinyfolk_job_scheduling_state.spec.luau
lune run tests/tinyfolk_job_scheduling_service_runtime_entrypoint.spec.luau
lune run tests/tinyfolk_haul_logistics_state.spec.luau
lune run tests/tinyfolk_haul_logistics_service_runtime_entrypoint.spec.luau
.\scripts\run-validation.ps1 -ChangedOnly
.\scripts\run-tests.ps1
```

## Acceptance criteria mapping

| Criterion | Approach |
|-----------|----------|
| AI performs bounded hauling and delivery | Proximity-gated pickup/deliver for scheduled haul jobs |
| Respects labor rules | General haul only; no specialist assignment |
| Delivery state visible for debugging | Logistics attributes + query API |
| Useful Studio Output logs | `[TinyfolkHaulLogisticsService]` structured lines |
