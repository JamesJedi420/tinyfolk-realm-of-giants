# TIN-256 Treasury Metal HUD Projection Kickoff (2026-06-20)

## Issue

- ID: TIN-256
- Title: Project session Metal into Giant treasury HUD
- Linear: https://linear.app/spectranoir/issue/TIN-256/project-session-metal-into-giant-treasury-hud
- Milestone: Progression, Economy, and Loadouts
- Related: [TIN-27](https://linear.app/spectranoir/issue/TIN-27/implement-metal-production-and-advanced-material-flow), [TIN-252](https://linear.app/spectranoir/issue/TIN-252/consolidate-giant-hud-right-stack-panels), [TIN-64](https://linear.app/spectranoir/issue/TIN-64/implement-giant-realm-resource-economy)

## Goal

Show session Metal stored in the Giant treasury HUD (`GiantHudStackClient` Treasury section) so TIN-27 metal flow is visible to realm owners.

## Context

TIN-27 ships Metal in `ResourceFlowState` (produced → in-transit → stored), forge refine, and warehouse delivery. Treasury presentation and projection still show only Essence/Wood/Stone. TIN-252 consolidated treasury into `GiantHudStackClient`.

`buildSessionTreasurySnapshot` in `GiantBuildModeService` reads `flowSnapshot.Wood.Stored` (capital S) but snapshots use lowercase `stored` — session W/S may always be 0 today. Fix while wiring Metal.

## Slice boundary

### In scope

1. `GiantRealmTreasuryPresentation` — add `sessionMetal`; extend summary (e.g. `Session E… W… S… M…`)
2. `GiantRealmTreasuryConfig.Attributes` — `SessionMetal = "GiantRealmSessionMetal"`
3. `GiantBuildModeService.buildSessionTreasurySnapshot` — read `Metal.stored`; fix W/S to use `.stored`
4. `applyTreasuryProjectionToPlayer` — set `SessionMetal` attribute
5. `GiantHudStackClient` — collect/pass `sessionMetal`; attribute refresh hook
6. Legacy `GiantTreasuryHudClient` parity if still used
7. Tests in `tests/giant_realm_treasury_presentation.spec.luau`
8. `docs/SYSTEM_BOUNDARIES.md` note; studio evidence doc (PENDING rows)

### Out of scope

- Ledger Metal or `resourceLedger` save-schema changes
- Construction metal spend (TIN-27 deferred)
- Village Status dedupe, HUD collapse persistence, theming (TIN-252 deferred)

## Key files

| Path | Purpose |
|------|---------|
| `src/ReplicatedStorage/Shared/GiantRealm/GiantRealmTreasuryPresentation.luau` | HUD model + summary |
| `src/ReplicatedStorage/Shared/Config/GiantRealmTreasuryConfig.luau` | Attribute names |
| `src/ServerScriptService/Services/GiantBuildModeService.server.luau` | Session snapshot + projection |
| `src/StarterPlayer/StarterPlayerScripts/Client/GiantHudStackClient.client.luau` | Treasury section consumer |
| `tests/giant_realm_treasury_presentation.spec.luau` | Presentation tests |

## Validation

```powershell
lune run tests/giant_realm_treasury_presentation.spec.luau
.\scripts\run-validation.ps1 -ChangedOnly
```

Studio: Play Solo as Giant after forge→warehouse Metal delivery; Treasury accordion shows session Metal > 0.

## Acceptance criteria

- After Metal stored via warehouse delivery, Giant treasury HUD shows session Metal > 0
- Session Wood/Stone read correctly from flow snapshot (`stored` field)
- Presentation spec covers Metal in summary/model
- Existing treasury tests remain green

## Session workflow

1. TIN-256 → **In Progress** in Linear
2. Branch: `tin-256-treasury-metal-hud-projection` from `master`
3. Implement presentation → config → server → client → tests → ship loop

## Deferred follow-ups

- Ledger Metal and construction metal spend (TIN-27)
- Giant HUD polish (TIN-252 deferred)
