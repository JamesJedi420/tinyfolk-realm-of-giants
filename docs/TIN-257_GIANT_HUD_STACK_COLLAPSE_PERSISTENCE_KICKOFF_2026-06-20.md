# TIN-257 Giant HUD Stack Collapse Persistence Kickoff (2026-06-20)

## Issue

- ID: TIN-257
- Title: Persist Giant HUD stack accordion collapse state
- Linear: https://linear.app/spectranoir/issue/TIN-257/persist-giant-hud-stack-accordion-collapse-state
- Milestone: Threat Progression and HUD
- Related: [TIN-252](https://linear.app/spectranoir/issue/TIN-252/consolidate-giant-hud-right-stack-panels), [TIN-256](https://linear.app/spectranoir/issue/TIN-256/project-session-metal-into-giant-treasury-hud)

## Goal

Persist Giant HUD stack accordion expand/collapse state across sessions via player-profile preference, following the `TrophyDisplayPolicyProfileState` pattern.

## Context

TIN-252 shipped `GiantHudStackClient` with collapsible sections but deferred persistence. All four sections (`Treasury`, `PenRationing`, `SocialEconomy`, `GiantEffects`) default to collapsed on every join.

## Slice boundary

### In scope

1. `GiantHudStackPreferenceProfileState` — profile key `giantHudStackPreference`, snapshot `expandedBySectionId`
2. `GiantHudStackConfig` — remote names and projected preference attribute
3. `GiantHudStackPreferenceService` — Giant role gate, profile load/save, attribute projection
4. `ProfilePersistenceGateway` — copy/save wiring for new profile key
5. `EventStateOwnershipModel` — namespace ownership
6. `GiantHudStackClient` — load preference on init, save on toggle
7. Pure tests for profile state
8. `docs/SYSTEM_BOUNDARIES.md` update; studio evidence doc (PENDING rows)

### Out of scope

- Unified theming/animation (TIN-252 deferred)
- Village Status dedupe
- Mobile/gamepad layout pass
- Realm-profile persistence

## Key files

| Path | Purpose |
|------|---------|
| `src/ReplicatedStorage/Shared/GiantRealm/GiantHudStackPreferenceProfileState.luau` | Pure profile preference logic |
| `src/ReplicatedStorage/Shared/Config/GiantHudStackConfig.luau` | Remotes + attribute names |
| `src/ServerScriptService/Services/GiantHudStackPreferenceService.server.luau` | Server orchestration |
| `src/StarterPlayer/StarterPlayerScripts/Client/GiantHudStackClient.client.luau` | Client consumer |
| `tests/giant_hud_stack_preference_profile_state.spec.luau` | Pure tests |

## Validation

```powershell
lune run tests/giant_hud_stack_preference_profile_state.spec.luau
.\scripts\run-validation.ps1 -ChangedOnly
```

Studio: expand Treasury + Social Economy, leave, rejoin as same Giant — sections restore expanded state.

## Acceptance criteria

- Section expand/collapse persists across rejoin for Giant role
- Unknown section ids rejected; defaults remain collapsed
- Non-Giant roles cannot mutate preference
- Profile gateway round-trips `giantHudStackPreference`

## Session workflow

1. TIN-257 → **In Progress** in Linear
2. Branch: `tin-257-giant-hud-stack-collapse-persistence` from `master`
3. Implement shared → service → gateway → client → tests → ship loop
