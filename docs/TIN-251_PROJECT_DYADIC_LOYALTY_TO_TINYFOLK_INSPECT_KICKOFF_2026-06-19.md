# TIN-251 Project Dyadic Loyalty to Tinyfolk Inspect Kickoff (2026-06-19)

## Issue

- ID: TIN-251
- Title: Project dyadic loyalty to Tinyfolk inspect
- Linear: https://linear.app/spectranoir/issue/TIN-251/project-dyadic-loyalty-to-tinyfolk-inspect
- Milestone: Progression, Economy, and Loadouts
- Related: [TIN-102](https://linear.app/spectranoir/issue/TIN-102/implement-tinyfolk-inspect-panel), [TIN-28](https://linear.app/spectranoir/issue/TIN-28/implement-social-economy-layer)

## Goal

Replace inspect panel `Loyalty: Unavailable` with real per-Tinyfolk favor/control from existing TIN-28 dyadic social economy maps.

## Context

TIN-102 inspect reads replicated per-player attributes on the selected Tinyfolk. `TinyfolkInspectState.ResolveLoyaltyLine()` is hardcoded to `Unavailable` because no loyalty attrs exist on Tinyfolk players today.

TIN-28 deferred work ships `SocialEconomyState.dyadicByUserId` with persistence via `dyadicRelations` on `GiantRealmSaveSchema`. Trophy events pass `targetUserId`; capture, labor, and ransom consumers resolve target-aware effect snapshots. `SocialEconomyService` projects **realm-level** favor/control onto the Giant owner only — dyadic per-target values never reach Tinyfolk player attributes.

Morale in inspect remains proxy-based (pen stress, fear, raid stage). This slice is **loyalty display only**, not a new per-Tinyfolk morale simulation.

## Slice boundary

### In scope

1. Per-Tinyfolk attribute names (e.g. `SocialDyadicFavor`, `SocialDyadicControl`) in `SocialEconomyConfig` or `TinyfolkInspectConfig`
2. Server projection in `SocialEconomyService` (or thin helper): set dyadic favor/control on in-realm Tinyfolk `Player` when a dyadic relation exists; clear on release, escape, or player leave
3. Projection refresh on social events, axis decay, and relevant player join/leave hooks
4. `TinyfolkInspectState.ResolveLoyaltyLine(input)` — format favor/control or loyalty band (reuse axis band patterns from `SocialEconomyPresentation`)
5. Register new attrs in `TinyfolkInspectConfig.Attributes`
6. Pure tests for loyalty line formatting; extend `social_economy_service_runtime_entrypoint` spec for projection/clear
7. Bounded `docs/SYSTEM_BOUNDARIES.md` note

### Out of scope

- New per-Tinyfolk morale simulation (separate issue)
- Server-curated inspect snapshot / remotes
- Covenant / miracle / domain expansion paths (TIN-28 long-term)
- Gameplay consumers beyond inspect display (can follow separately)
- Tinyfolk or cross-role inspect viewers

## Field mapping

| Inspect field | Source | Notes |
|---------------|--------|-------|
| Loyalty | `SocialDyadicFavor`, `SocialDyadicControl` (proposed) | Band or `Favor N / Control N`; `Unavailable` when no dyadic entry |

## Architecture

```
SocialEconomyService social event / decay / load
  → SocialEconomyState.dyadicByUserId
  → projectDyadicAttributes(tinyfolkPlayer, relation?)
TinyfolkInspectClient (existing)
  → TinyfolkInspectState.ResolveLoyaltyLine(attrs)
  → TinyfolkInspectPresentation.BuildPanelModel
```

Inspect client unchanged except reading new registered attributes. No new remotes.

## Key files

| Path | Purpose |
|------|---------|
| `src/ServerScriptService/Services/SocialEconomyService.server.luau` | Per-Tinyfolk dyadic attribute projection |
| `src/ReplicatedStorage/Shared/GiantRealm/SocialEconomyState.luau` | Dyadic lookup, `ResolveEffectiveAxes` |
| `src/ReplicatedStorage/Shared/GiantRealm/TinyfolkInspectState.luau` | `ResolveLoyaltyLine` |
| `src/ReplicatedStorage/Shared/Config/TinyfolkInspectConfig.luau` | Attribute registry |
| `src/ReplicatedStorage/Shared/Config/SocialEconomyConfig.luau` | Attribute name constants |
| `tests/tinyfolk_inspect_state.spec.luau` | Loyalty line specs |
| `tests/social_economy_service_runtime_entrypoint.spec.luau` | Projection/clear specs |

## Validation

```powershell
lune run tests/tinyfolk_inspect_state.spec.luau
lune run tests/social_economy_service_runtime_entrypoint.spec.luau
.\scripts\run-validation.ps1 -ChangedOnly
.\scripts\run-tests.ps1
```

Studio:

- Capture Tinyfolk → inspect loyalty shows favor/control (not `Unavailable`)
- Tinyfolk with no dyadic entry → `Unavailable` or documented default
- Release / escape → loyalty attrs cleared; inspect line updates
- Social trophy event on target → loyalty attrs refresh live on inspect panel

## Acceptance criteria

| Criterion | Approach |
|-----------|----------|
| Loyalty no longer always unavailable | Dyadic attrs projected when relation exists |
| Server-authoritative | Projection from `SocialEconomyService`, not client inference |
| Cleared on exit | Release/escape/leave clears target attrs |
| Inspect live refresh | Existing attribute hooks pick up projection changes |
| Tests green | State + service runtime specs extended |

## Session workflow

1. Move TIN-251 → **In Progress** in Linear
2. Branch: `tin-251-project-dyadic-loyalty-to-tinyfolk-inspect` from `master`
3. Implement: config attrs → server projection → inspect state → tests → audit → ship loop

## Deferred follow-ups

- Per-Tinyfolk morale simulation (distinct from pen morale and loyalty)
- Gameplay consumers of per-Tinyfolk dyadic attrs (compliance gates, AI)
- Server-curated inspect snapshot
- Loyalty tone bands on selection highlight (TIN-250 uses custody tone only)
