# TIN-101 Village Upgrade System Slice C Kickoff (2026-06-08)

## Issue
- ID: TIN-101
- Title: Implement village upgrade system
- Linear: https://linear.app/spectranoir/issue/TIN-101/implement-village-upgrade-system

## Slice C1 boundary
Add the four remaining TIN-101 worksite kinds with the same upgrade pipeline established in Slices A and B:

- **Farm** (`Farm_*`) — production effect (food/crop output)
- **Pen** (`Pen_*`) — capacity effect (livestock/containment throughput)
- **Guard tower** (`GuardTower_*`) — defense effect (tower pressure or zone coverage)
- **Giant dwelling** (`GiantDwelling_*`) — capacity or production effect (realm Giant housing / power budget — design lock required)

For each kind, ship only when **both** gates are satisfied:

1. **Map contract** — authored anchor part in `src/Workspace/Map/Stations/<Kind>/Layout.model.json`, registered in `RealmAssemblyPrototypeFixture.stations`, debug label in `DebugLabels` if applicable.
2. **Effect owner** — a runtime service accepts level modifiers from `VillageWorksiteUpgradeService` query seams (same pattern as `StationService`, `ResourceFlowState`, `ShrineService`).

### Per-kind delivery checklist
| Kind | Prefix | Effect kind | Config | State resolver | Service hook | F-key client |
|------|--------|-------------|--------|----------------|--------------|--------------|
| Farm | `Farm_` | production | cost + production multipliers | `ResolveWorksiteKind` | farm production service | `resolveUpgradeableWorksiteId` |
| Pen | `Pen_` | capacity | cost + capacity multipliers | `ResolveWorksiteKind` | pen/containment service | same |
| Guard tower | `GuardTower_` | defense | cost + defense multipliers (new table) | `ResolveWorksiteKind` | guard/tower or control service | same |
| Giant dwelling | `GiantDwelling_` | TBD | cost + modifiers | `ResolveWorksiteKind` | dwelling/build service | same |

### Shared plumbing (all kinds)
- Extend `StationConfig` (or dedicated config module) with name prefixes and default IDs.
- Extend `VillageWorksiteUpgradeConfig.UpgradeCostsByKindAndLevel` for each kind.
- Extend `VillageWorksiteUpgradeState.WorksiteKinds`, `ResolveWorksiteKind`, `ResolveEffectKind`, and modifier helpers as needed.
- Reuse existing spend path: `GiantBuildModeService.SpendWorksiteUpgradeCost` / `RollbackWorksiteUpgradeSpend`.
- Reuse persistence: `worksiteUpgrades` on Giant realm save root (no schema migration expected).
- Reuse client flow: `InteractionResolver` → `VillageWorksiteUpgradeRequest` → `GiantWorksiteUpgradeFeedbackClient`.

### Acceptance criteria (C1)
- Each shipped kind has at least one authored map anchor and passes topology/assembly fixture checks.
- Giant F-key upgrade at the worksite advances level 0→1→2→3 with ledger spend and persistence round-trip.
- Upgrade level modifies the agreed production/capacity/defense metric in the owning service (test-backed).
- Unsupported or unmapped worksite IDs still reject with deterministic reasons.
- No regression to Slices A/B kinds or existing upgrade board flow.

## Prerequisites (blockers before merge)
- **Map authoring** for at least the first kind in scope (recommended start: `Farm_A` — Granary already reserved for future food routing).
- **Effect contract sign-off** per kind: what level 1/2/3 changes numerically (multiplier table or new `DefenseMultipliersByLevel`).
- **Giant dwelling ownership decision** — fixed map worksite vs `GiantBuildModeService` placed structure; do not implement until decided.

## Deferred (Slice C2+)
- Upgrade board UX unification (presentation-only hub or board-as-menu for worksite upgrades).
- Deprecating session-essence board buffs (`PowerCore` / `IronStride`) in favor of dwelling/shrine upgrades.
- Kinds without map anchors or effect owners (prefix-only stubs are out of scope).

## Key files
### Existing (extend)
- `src/ReplicatedStorage/Shared/Config/StationConfig.luau`
- `src/ReplicatedStorage/Shared/Config/VillageWorksiteUpgradeConfig.luau`
- `src/ReplicatedStorage/Shared/GiantRealm/VillageWorksiteUpgradeState.luau`
- `src/ReplicatedStorage/Shared/GiantRealm/VillageWorksiteUpgradePresentation.luau`
- `src/ServerScriptService/Services/VillageWorksiteUpgradeService.server.luau`
- `src/StarterPlayer/StarterPlayerScripts/Client/InteractionResolver.client.luau`
- `src/ReplicatedStorage/Shared/RealmAssembly/RealmAssemblyPrototypeFixture.luau`

### New (per kind, as needed)
- `src/Workspace/Map/Stations/Farm/Layout.model.json`
- `src/Workspace/Map/Stations/Pen/Layout.model.json`
- `src/Workspace/Map/Stations/GuardTower/Layout.model.json`
- `src/Workspace/Map/Stations/GiantDwelling/Layout.model.json`
- Owning service module(s) for farm/pen/guard/dwelling effect hooks

### Tests
- `tests/village_worksite_upgrade_state.spec.luau`
- `tests/village_worksite_upgrade_presentation.spec.luau`
- `tests/village_worksite_upgrade_service_runtime_entrypoint.spec.luau`
- New specs per effect owner as hooks land

## Validation
```powershell
lune run tests/village_worksite_upgrade_state.spec.luau
lune run tests/village_worksite_upgrade_presentation.spec.luau
lune run tests/village_worksite_upgrade_service_runtime_entrypoint.spec.luau
.\scripts\run-validation.ps1 -ChangedOnly
.\scripts\run-tests.ps1
```

Studio (when map contracts change):
```powershell
rojo build default.project.json -o TinyfolkRealmOfGiants.rbxlx
```
Open built place; confirm F-key upgrade at new anchor parts and effect feedback in Output/HUD.

## Recommended implementation order
1. Farm (`Farm_A` + food production hook → Granary routing alignment)
2. Pen (containment/livestock capacity hook)
3. Guard tower (defense hook — likely remote control or capture-adjacent)
4. Giant dwelling (after ownership decision)

Ship each kind as a focused PR or sequential commits within one C1 branch; do not batch unmapped kinds.
