# TIN-240 Village Upgrade System Slice C2 Kickoff (2026-06-09)

## Issue
- ID: TIN-240 (follows TIN-101 C1 completion)
- Linear: https://linear.app/spectranoir/issue/TIN-240/village-upgrade-system-slice-c2-hub-ux-deprecate-board-buffs
- Parent context: [TIN-101](https://linear.app/spectranoir/issue/TIN-101/implement-village-upgrade-system) Slice C2+ deferred items
- Milestone: Progression, Economy, and Loadouts

## Problem
Giants now have **two parallel upgrade surfaces** with no unified presentation:

| Surface | Interaction | Currency | Persistence | Effects today |
|---------|-------------|----------|-------------|---------------|
| `GiantUpgradeBoard_*` | F at board → ordered `PowerCore` / `IronStride` | Session essence (`GiantEssenceSession`) | Session attributes `GiantUpgrade_*` | `maxHealth`, `walkSpeed`, `powerBudget`, `movementControl` |
| Village worksites | F at station anchor → level 0→3 | Realm ledger wood/stone/essence | `worksiteUpgrades` on save root | Production / capacity / defense / housing per kind |

Players must discover worksite upgrades by walking the map; the board still sells legacy session buffs that overlap thematically with shrine (power/essence) and dwelling (Giant scale).

## Slice C2 boundary (three sub-slices)

### C2a — Upgrade board UX unification (presentation first)
**Goal:** One readable Giant upgrade hub at `GiantUpgradeBoard_A` that surfaces both progression tracks without merging spend paths yet.

**In scope:**
- Shared presentation module building a hub snapshot (board next step + upgradeable worksite summary)
- Client hub panel at the board (levels, costs, effect labels) — presentation-only or board-as-menu dispatch
- Server query seam exposing hub snapshot for debug/tests
- `InteractionResolver` priority: when Giant is at board with hub enabled, board action shows hub instead of blind `progress_next`

**Out of scope for C2a:**
- Removing `PowerCore` / `IronStride`
- Changing spend ledgers
- New effect owners

**Key files:**
- `src/ReplicatedStorage/Shared/Config/UpgradeBoardConfig.luau`
- `src/ReplicatedStorage/Shared/GiantRealm/VillageWorksiteUpgradePresentation.luau` (extend or sibling hub module)
- `src/StarterPlayer/StarterPlayerScripts/Client/UpgradeBoardClient.client.luau`
- `src/StarterPlayer/StarterPlayerScripts/Client/GiantWorksiteUpgradeFeedbackClient.client.luau`
- `src/StarterPlayer/StarterPlayerScripts/Client/InteractionResolver.client.luau`
- `src/ServerScriptService/Services/UpgradeBoardService.server.luau`
- `src/ServerScriptService/Services/VillageWorksiteUpgradeService.server.luau`

### C2b — Deprecate session-essence board buffs
**Goal:** Retire `PowerCore` and `IronStride` as session essence purchases; re-home their gameplay effects on persisted worksite upgrades.

**Proposed effect mapping (sign-off before coding):**

| Legacy board buff | Effect today | New owner |
|-------------------|--------------|-----------|
| `PowerCore` | `powerBudgetBonus` + `maxHealthBonus` | **Shrine** upgrade levels → essence cap / tribute scaling feeds `GiantEffect_PowerBudget` |
| `IronStride` | `walkSpeedBonus` + `movementControlBonus` | **Giant dwelling** upgrade levels → Giant locomotion presentation (separate from housing slot count) |

**In scope:**
- Mark board options deprecated / hidden from hub “purchase” path
- `UpgradeBoardService.resolveEffects` reads shrine + dwelling upgrade APIs instead of `GiantUpgrade_*` session attributes
- Migration: existing session `GiantUpgrade_*` flags ignored or one-time mapped for dev sessions only
- Tests proving board no longer spends essence for PowerCore/IronStride; effects derive from worksite levels

**Out of scope:**
- `PowerBudgetProduction` as a new effect kind (C2c)
- Rebalancing numeric tables beyond parity smoke targets

### C2c — PowerBudgetProduction (optional / later)
Only if design explicitly adds dwelling or station **power generation**. Separate effect contract:

- `EffectKind = PowerBudgetProduction`
- `SourceType = StationUpgrade`
- Must not reuse `GiantHousingCapacity` multiplier table

**Deferred until explicit design sign-off.**

## Prerequisites
- TIN-101 C1 complete (all worksite kinds + effect owners shipped)
- C2b effect mapping approved before implementation

## Acceptance criteria (full C2)
- [ ] Giant at upgrade board sees unified hub: board track status + worksite upgrade summary
- [ ] `PowerCore` / `IronStride` no longer purchasable via session essence
- [ ] `GiantEffect_PowerBudget` (and related attributes) derive from shrine/dwelling upgrade levels
- [ ] Worksite F-key upgrade flow unchanged for map anchors
- [ ] No regression to village worksite persistence or ledger spend
- [ ] Test-backed presentation and effect resolution

## Recommended ship order
1. **C2a** — hub presentation + query API (`tin-102-c2a-upgrade-hub`)
2. **C2b** — deprecate board buffs + effect re-home (`tin-102-c2b-deprecate-board-buffs`)
3. **C2c** — only if power production is approved

## Validation
```powershell
lune run tests/village_worksite_upgrade_presentation.spec.luau
lune run tests/village_worksite_upgrade_service_runtime_entrypoint.spec.luau
lune run tests/upgrade_board_service_runtime_entrypoint.spec.luau  # if present
.\scripts\run-validation.ps1 -ChangedOnly
.\scripts\run-tests.ps1
```

Studio: F at `GiantUpgradeBoard_A` shows hub; confirm worksite rows match map levels; after C2b confirm PowerCore/IronStride no longer spend essence.

## Non-goals
- GiantBuildMode structure placement changes
- Tinyfolk-side upgrade paths (TIN-25)
- Full UI polish / final balance pass
