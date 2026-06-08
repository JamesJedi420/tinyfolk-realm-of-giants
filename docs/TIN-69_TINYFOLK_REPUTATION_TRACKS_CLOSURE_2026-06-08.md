# TIN-69 Tinyfolk Reputation Tracks Closure (2026-06-08)

## Issue
- ID: TIN-69
- Title: Implement Tinyfolk reputation tracks
- Linear: https://linear.app/spectranoir/issue/TIN-69/implement-tinyfolk-reputation-tracks

## Shipped
- Seven persistent reputation tracks: Escapist, Saboteur, Rescuer, Scout, Thief, Diplomat, Folk Hero.
- `ReputationState.ApplyOutcome` updates tracks from escape and containment custody-end outcomes.
- Anti-farming via per-track cooldowns, repeat windows, and daily caps.
- Cosmetic title unlocks and loadout-safe trait unlocks (no permanent power modifiers).
- Runtime wiring in `EscapeOutcomeResolver` and `ContainmentRewardResolver` with `reputation_update` EventLog entries.
- Profile persistence via `ProfilePersistenceGateway`; title query API for presentation surfaces.

## Key files
- `src/ReplicatedStorage/Shared/Reputation/ReputationState.luau`
- `src/ServerScriptService/Services/EscapeOutcomeResolver.luau`
- `src/ServerScriptService/Services/ContainmentRewardResolver.luau`
- `src/ReplicatedStorage/Shared/RoleLoadout/RoleLoadoutState.luau`
- `src/ServerScriptService/Services/ProfilePersistenceGateway.luau`

## Validation
```powershell
lune run tests/reputation_state.spec.luau
lune run tests/reputation_presentation.spec.luau
lune run tests/escape_outcome_resolver.spec.luau
lune run tests/containment_reward_resolver.spec.luau
lune run tests/role_loadout_state.spec.luau
```
