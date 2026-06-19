# TIN-28 Social Economy Modifier — Capture Intimidation Gate — Kickoff

**Date:** 2026-06-19  
**Parent:** [TIN-28](https://linear.app/spectranoir/issue/TIN-28/implement-social-economy-layer)

## Slice boundary

- Read `SocialEconomyService.GetEffectSnapshot().controlIntimidationBonus` from `CaptureService.resolveMoraleCaptureGate`.
- Extend `PenRationingState.ResolveCaptureMoraleCheck` with optional `intimidationBonus` applied only on the probabilistic sub-threshold roll branch.
- Graceful degradation when `_SocialEconomyService_QueryAPI` is absent (bonus = 1).

## Semantics

- `controlIntimidationBonus = 1 + control / 200` (from `SocialEconomyState.ResolveEffectSnapshot`).
- Sure-threshold morale path unchanged (`morale >= MoraleCaptureSureThreshold` always passes).
- Probabilistic path compares roll against `clamp(floor(morale * intimidationBonus), 0, 100)`.
- Depleted morale (`<= 0`) hard-blocks regardless of bonus.

## Out of scope

- `favorComplianceBonus` / labor compliance (future slice).
- Ransom post/settle gates.
- Decay, caps, anti-snowball balancing.
- HUD polish, per-Tinyfolk dyadic maps, new config tables.

## Key files

| Path | Change |
|------|--------|
| `src/ReplicatedStorage/Shared/GiantRealm/PenRationingState.luau` | Optional intimidation bonus on morale roll |
| `src/ServerScriptService/Services/CaptureService.server.luau` | QueryAPI consumer seam |
| `tests/pen_rationing_state.spec.luau` | Pure-state bonus cases |
| `tests/capture_service_runtime_entrypoint.spec.luau` | Runtime integration with mocked SocialEconomy API |

## Validation

```powershell
lune run tests/pen_rationing_state.spec.luau
lune run tests/capture_service_runtime_entrypoint.spec.luau
lune run tests/social_economy_state.spec.luau
lune run tests/social_economy_service_runtime_entrypoint.spec.luau
.\scripts\run-validation.ps1 -ChangedOnly
```
