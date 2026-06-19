# TIN-28 Social Economy Modifier — Capture Intimidation Gate — Closure

**Date:** 2026-06-19  
**Parent:** [TIN-28](https://linear.app/spectranoir/issue/TIN-28/implement-social-economy-layer)

## Shipped

- `PenRationingState.ResolveCaptureMoraleCheck` — optional `intimidationBonus` on probabilistic sub-threshold roll only.
- `CaptureService` — reads `_SocialEconomyService_QueryAPI.GetEffectSnapshot().controlIntimidationBonus` with neutral fallback when API absent.
- Unit and runtime specs for bonus on/off and service integration.

## Validation

```powershell
lune run tests/pen_rationing_state.spec.luau
lune run tests/capture_service_runtime_entrypoint.spec.luau
lune run tests/social_economy_state.spec.luau
lune run tests/social_economy_service_runtime_entrypoint.spec.luau
.\scripts\run-validation.ps1 -ChangedOnly
```

All focused specs passed locally.

## Deferred (remaining TIN-28 scope)

- `favorComplianceBonus` / labor compliance consumer.
- Ransom post/settle gates.
- Decay, caps, anti-snowball balancing.
- HUD polish, per-Tinyfolk dyadic maps.
