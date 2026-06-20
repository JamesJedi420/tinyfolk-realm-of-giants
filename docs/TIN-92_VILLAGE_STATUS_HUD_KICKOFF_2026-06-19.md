# TIN-92 Village Status HUD Kickoff (2026-06-19)

## Issue

- ID: TIN-92
- Title: Implement village status HUD
- Linear: https://linear.app/spectranoir/issue/TIN-92/implement-village-status-hud
- Milestone: Threat Progression and HUD

## Goal

Show village-wide health and pressure in one readable Giant-facing panel. Server-authoritative snapshot → player attribute projection → client HUD. Danger states visibly marked; text sized for Giant camera scale.

## Context

Recent HUD slices ship vertical panels on the right (Treasury, Social Economy, Pen Rationing, Labor Job). TIN-92 adds a **consolidated village summary** without removing those panels in this slice.

Follows the established pattern: pure `Shared/` presentation + server projection on realm-owner Giant + `*.client.luau` read-only consumer (see TIN-33, TIN-28 HUD, `GiantTreasuryHudClient`).

## Slice boundary (slice 1)

### In scope

1. `VillageStatusHudConfig` — attribute names, danger thresholds, layout constants
2. `VillageStatusState` — pure snapshot builder + danger band resolution from typed inputs
3. `VillageStatusHudPresentation` — pure HUD model (title, summary lines, overall `tone`)
4. Server projection — aggregate existing query APIs; set attributes on realm-owner Giant player
   - Prefer a thin `VillageStatusProjectionService` **or** hook the existing treasury refresh loop in `GiantBuildModeService` (avoid duplicate heartbeats)
5. `VillageStatusHudClient` — Giant-only screen panel; top-left placement; accent color by tone
6. Tests: `village_status_state.spec.luau`, `village_status_hud_presentation.spec.luau`
7. `docs/SYSTEM_BOUNDARIES.md` — bounded village status projection note

### Out of scope

- **Rebellion pressure** — no rebellion simulation exists; do not fabricate values
- Final UI polish, animations, art pass
- Removing or merging existing specialized HUDs
- New morale, rebellion, escape, or population simulation systems
- Persistence schema changes
- Tinyfolk-facing village panel (Giant-only for slice 1)

## Metric mapping (issue → existing state)

| Issue metric | Source | Projection notes |
|--------------|--------|------------------|
| Food | `ResourceFlowState.GetSnapshot().Food` | stored, produced, inTransit |
| Production | Resource flow totals + `_TinyfolkJobSchedulingService_QueryAPI.GetDebugSnapshot()` | W/S/F/M produced; `assignmentCount` as active jobs |
| Morale | `PenRationingConfig.StateAttributes.CustodianMorale` on Giant; pen shortfall attrs | Reuse thresholds from `PenRationingConfig.MoraleCaptureSureThreshold` |
| Population | `_EmergencyReinforcementService_QueryAPI.GetActiveTinyfolkCount()`; pen `ActiveCaptiveCount`; scheduling `workerCount` | Label as **Raiders \| Workers \| Captives** (proxies until TIN-16) |
| Escape risk | Derived band from raider count + captives + morale/shortfall danger | Coarse pressure label (`calm` / `elevated` / `critical`) |
| Rebellion | — | **Deferred** — omit line or show unavailable; document in closure |

## Danger bands (initial thresholds — tune in pure tests)

| Signal | Warning | Critical |
|--------|---------|----------|
| Food stored | &lt; 30 | &lt; 10 |
| Pen shortfall | `LastFoodShortfall` or `ConsecutiveShortfallTicks` &gt; 0 | streak ≥ 3 |
| Morale | &lt; `MoraleCaptureSureThreshold` (50) | ≤ 0 |
| Active raiders | ≥ 2 | ≥ 4 |
| Overall HUD tone | worst-of contributing metrics | |

## Architecture

```
ResourceFlowState ──┐
PenRationing state ─┼→ VillageStatusState.BuildSnapshot → projection → Giant player attrs
EmergencyReinforcement ─┤                                      ↓
JobScheduling debug ──┤                          VillageStatusHudClient (Giant only)
SocialEconomy (opt) ──┘                          ← VillageStatusHudPresentation
```

## Key files (new)

| Path | Purpose |
|------|---------|
| `src/ReplicatedStorage/Shared/Config/VillageStatusHudConfig.luau` | Attributes, thresholds, strings |
| `src/ReplicatedStorage/Shared/GiantRealm/VillageStatusState.luau` | Pure snapshot + danger resolution |
| `src/ReplicatedStorage/Shared/GiantRealm/VillageStatusHudPresentation.luau` | Pure HUD model |
| `src/ServerScriptService/Services/VillageStatusProjectionService.server.luau` | Aggregate + project (or fold into `GiantBuildModeService`) |
| `src/StarterPlayer/StarterPlayerScripts/Client/VillageStatusHudClient.client.luau` | Client panel |
| `tests/village_status_state.spec.luau` | Pure state tests |
| `tests/village_status_hud_presentation.spec.luau` | Pure presentation tests |

## Key files (read first)

| Path | Why |
|------|-----|
| `GiantBuildModeService.server.luau` — `applyTreasuryProjectionToPlayer` | Realm-owner projection pattern |
| `GiantRealmTreasuryPresentation.luau` | Presentation + summary string pattern |
| `SocialEconomyHudClient.client.luau` | Accent tone, Giant-only gate, attribute hooks |
| `PenRationingHudPresentation.luau` | Morale / shortfall tone logic |
| `TinyfolkLaborJobHudPresentation.luau` | Job readout patterns |
| `ResourceFlowState.luau` — `GetSnapshot()` | Food / production inputs |
| `PenRationingService.server.luau` | Morale + pen attrs (read server-side, not client workspace scan) |
| `EmergencyReinforcementService.server.luau` — `GetActiveTinyfolkCount` | Raider population proxy |
| `TinyfolkJobSchedulingService.server.luau` — `GetDebugSnapshot` | Worker / assignment counts |

## Server query seams

- `ResourceFlowState.GetSnapshot()`
- `_PenRationingService_QueryAPI.GetCustodianMorale` / pen part state on server
- `_EmergencyReinforcementService_QueryAPI.GetActiveTinyfolkCount`
- `_TinyfolkJobSchedulingService_QueryAPI.GetDebugSnapshot`
- `_SocialEconomyService_QueryAPI.GetEffectSnapshot` (optional social pressure sub-line: favor/control)

## Client layout

- **Position:** top-left (`AnchorPoint` 0,0; ~`UDim2.fromScale(0.02, 0.12)`) — right edge already hosts Treasury (~0.28), Social (~0.36), Pen/Labor lower
- **Font:** GothamBold 16–18 title; Gotham 14–16 body (Giant-scale readability)
- **Visibility:** `Role == Giant` and village snapshot attributes present

## Example panel copy

```
Village Status
Raiders 3 | Workers 5 | Captives 2
Food 120 stored (+8 transit) | Morale 42
Production W+12 S+4 | Jobs 2 active
Escape pressure: Elevated
```

## Acceptance criteria (narrowed)

| Criterion | Approach |
|-----------|----------|
| Core village stats visible | Single Giant panel with population, food, morale, production, escape pressure |
| Server-driven | Projection service sets realm-owner player attributes; client read-only |
| Danger marked | Per-metric + overall `tone` (`neutral` / `warning` / `critical`) with accent color |
| Giant camera scale | Top-left panel, larger text, no dependency on world part proximity |
| No fabricated sim | Rebellion omitted; population uses labeled proxies |

## Validation

```powershell
lune run tests/village_status_state.spec.luau
lune run tests/village_status_hud_presentation.spec.luau
.\scripts\run-validation.ps1 -ChangedOnly
.\scripts\run-tests.ps1
```

Studio (required by issue):

- Giant role → panel visible with live food/morale/raider updates
- Danger accent changes on shortfall, low morale, elevated raider count

## Session workflow

1. Move TIN-92 → **In Progress** in Linear
2. Branch: `tin-92-village-status-hud` from `master`
3. Implement: shared → server projection → client → tests → audit → ship loop per `.cursor/rules/pr-ship-workflow.mdc`

## Deferred follow-ups (separate issues)

- Rebellion / subversion pressure when simulation exists (TIN-183-adjacent)
- HUD consolidation (merge or collapse right-stack panels)
- TIN-102 per-Tinyfolk inspect panel
- TIN-83 dual-scale camera layout tuning
