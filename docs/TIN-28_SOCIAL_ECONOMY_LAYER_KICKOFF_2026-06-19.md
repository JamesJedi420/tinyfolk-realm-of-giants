# TIN-28 Social Economy Layer — Kickoff

**Date:** 2026-06-19  
**Issue:** [TIN-28](https://linear.app/spectranoir/issue/TIN-28/implement-social-economy-layer)

## Slice boundary (foundation)

- `SocialEconomyConfig` — axis bounds (0–100), placeholder delta table, `StateAttributes`, `EventKinds` with loyalty/fear aliases.
- `SocialEconomyState` — pure `ApplySocialEvent`, `ResolveEffectSnapshot`, idempotent by `operationId`.
- `SocialEconomyService` — `_SocialEconomyService_QueryAPI`, realm-owner attribute projection (session-only).
- `SocialEconomyPresentation` — coarse debug labels for Studio inspection.
- Minimal `TrophyService` producers: `capture_success`, `negotiated_release`, `containment_escape_failure`.
- Realm-owner debug attributes: `SocialEconomyFavor`, `SocialEconomyControl`, effect snapshot fields.

## System boundary hygiene

| Existing term | System | TIN-28 boundary |
|---------------|--------|-----------------|
| Fear exposure / panic | `TinyfolkStatusService` | Separate timed-condition pipeline |
| Score `control` category | `ScoreConfig` | Match scoring, not social control axis |
| Remote control stations | `RemoteControlStationState` | Route pressure mechanics |
| Custodian morale | `PenRationingState` | Operational pen rationing gate |
| Giant reputation ladder | `GiantReputationState` | Persistent trophy-derived rank — parallel, not merged |
| Tinyfolk reputation tracks | `ReputationState` | Player-profile partition |

## Deferred

- Persistence (`GiantRealmSaveSchema`, `EventStateOwnershipModel` namespace).
- Final balancing (decay, caps, anti-snowball).
- Gameplay modifier consumption (labor, capture, ransom).
- HUD polish beyond debug attributes.
- Per-Tinyfolk dyadic favor/fear maps.
- Covenant / miracle / domain expansion identity paths.

## Validation

```powershell
lune run tests/social_economy_state.spec.luau
lune run tests/social_economy_service_runtime_entrypoint.spec.luau
lune run tests/trophy_service_runtime_entrypoint.spec.luau
.\scripts\run-validation.ps1 -ChangedOnly
```
