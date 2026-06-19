# TIN-28 Social Economy Deferred Work — Closure

**Date:** 2026-06-19  
**Issue:** [TIN-28](https://linear.app/spectranoir/issue/TIN-28/implement-social-economy-layer)

## Shipped

### Balancing
- Axis decay toward defaults, bonus caps, trophy delta diminishing returns.
- `SocialEconomyService` heartbeat decay + `AdvanceDecayForTests`.

### Labor compliance
- `LaborComplianceState.ApplyComplianceYield` + `StationService` / `ShrineService` production yield multiplier via `favorComplianceBonus`.

### Ransom gates
- `RansomSocialGateState` — control minimum for post, favor-discounted PaymentFood settle cost.
- `RansomBoardService` integration with dyadic-aware effect resolution.

### HUD polish
- `SocialEconomyHudClient` for Giant realm-owner attribute projection.
- Extended `SocialEconomyPresentation` and `PenRationingHudPresentation` intimidation readout.

### Dyadic maps
- `dyadicByUserId` on `SocialEconomyState`, persistence via `dyadicRelations` on save root.
- `ResolveEffectiveAxes` / target-aware `GetEffectSnapshot`.
- Trophy events pass `targetUserId`; capture, labor, and ransom consumers use target context.

## Validation

```powershell
lune run tests/social_economy_state.spec.luau
lune run tests/social_economy_service_runtime_entrypoint.spec.luau
lune run tests/labor_compliance_state.spec.luau
lune run tests/ransom_social_gate_state.spec.luau
lune run tests/social_economy_presentation.spec.luau
lune run tests/giant_realm_save_schema.spec.luau
.\scripts\run-validation.ps1 -ChangedOnly
.\scripts\run-tests.ps1
```

## Deferred

- Covenant / miracle / domain expansion identity paths (explicitly out of TIN-28).
