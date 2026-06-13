# TIN-85 Tinyfolk Struggle and Escape Minigame Closure (2026-06-13)

## Issue

- ID: TIN-85
- Title: Implement Tinyfolk struggle and escape minigame
- Linear: https://linear.app/spectranoir/issue/TIN-85/implement-tinyfolk-struggle-and-escape-minigame

## Shipped

- `CaptivityEscapeProgressState` — deterministic struggle progress, ally assist, idle decay, and containment suppression reset.
- `CaptureConfig` — struggle/assist/decay tuning plus readable captivity escape attributes.
- `CapturePersistenceRules` — `struggle` and `ally_rescue_assist` escape actions.
- `CaptivityEscapeService` — server-authoritative struggle, ally assist, containment suppression, and query API.
- `CaptivityEscapeClient` — minimal `F` struggle and `R` ally assist remotes.
- Struggle completion resolves custody through `CaptureService.ResolveCustodyEnd(..., "released")`.
- Containment suppression promotes to contained and resets/suppresses escape progress.

## Acceptance mapping

| Criterion | Status |
|-----------|--------|
| Captured Tinyfolk can build escape progress | PASS — struggle + ally assist increment progress |
| Escape progress resets or decays under defined rules | PASS — idle decay + containment suppression reset |
| Nearby allies can accelerate rescue | PASS — ally assist + nearby ally struggle bonus |
| Giant can suppress escape by reaching valid containment zone | PASS — containment zone check + promote to contained |
| All logic is server-authoritative | PASS — shared state + service orchestration |

## Deferred

- Raid/trade/ransom disconnect paths (from TIN-74).
- Studio spot-check for reconnect spawn placement.
- HUD/VFX/audio polish for struggle meter.

## Validation

```powershell
.\scripts\run-validation.ps1 -ChangedOnly
lune run tests/captivity_escape_progress_state.spec.luau
lune run tests/captivity_escape_service_runtime_entrypoint.spec.luau
lune run tests/capture_persistence_rules.spec.luau
lune run tests/capture_service_runtime_entrypoint.spec.luau
lune run tests/rescue_contract_service_runtime_entrypoint.spec.luau
.\scripts\run-tests.ps1
```
