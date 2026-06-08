# TIN-63 Realm Escape Victory Outcomes Closure (2026-06-08)

## Issue
- ID: TIN-63
- Title: Implement realm escape victory outcomes
- Linear: https://linear.app/spectranoir/issue/TIN-63/implement-realm-escape-victory-outcomes

## Shipped
- `EscapeOutcomeResolver` awards score from difficulty + carried loot, appends player `escapeHistory`, records Giant defense history, and applies reputation updates.
- `EscapeService` relocates escaped Tinyfolk to the shared hub (final exit, fallback, transport paths).
- Durable `escapeOutcomeIdempotency` prevents duplicate loot/score/profile/defense side effects.

## Deferred
- Map knowledge rewards (listed in scope, not in acceptance criteria).

## Key files
- `src/ServerScriptService/Services/EscapeOutcomeResolver.luau`
- `src/ServerScriptService/Services/EscapeService.server.luau`
- `src/ServerScriptService/Services/GiantBuildModeService.server.luau`

## Validation
```powershell
lune run tests/escape_outcome_resolver.spec.luau
lune run tests/escape_service_runtime_entrypoint.spec.luau
lune run tests/reputation_state.spec.luau
```
