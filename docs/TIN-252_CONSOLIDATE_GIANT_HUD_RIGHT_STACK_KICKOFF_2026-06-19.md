# TIN-252 Consolidate Giant HUD Right-Stack Panels Kickoff (2026-06-19)

## Issue

- ID: TIN-252
- Title: Consolidate Giant HUD right-stack panels
- Linear: https://linear.app/spectranoir/issue/TIN-252/consolidate-giant-hud-right-stack-panels
- Milestone: Threat Progression and HUD
- Related: [TIN-92](https://linear.app/spectranoir/issue/TIN-92/implement-village-status-hud)

## Goal

Reduce Giant HUD vertical clutter by consolidating the right-stack panels into a collapsible accordion. Village Status (TIN-92) stays on the left as the summary anchor.

## Context

Recent HUD slices each ship a standalone `ScreenGui` with hard-coded Y positions on the right edge:

| Panel | Client | Anchor Y |
|-------|--------|----------|
| Giant Effects | `GiantEffectHudClient` | 0.14 |
| Pen Rationing | `PenRationingHudClient` | 0.24 |
| Treasury | `GiantTreasuryHudClient` | 0.28 |
| Social Economy | `SocialEconomyHudClient` | 0.36 |

Treasury and Pen Rationing overlap at Giant camera scale. TIN-92 adds `VillageStatusHudClient` on the **left** (0.02, 0.12) as a consolidated village summary — the right-stack detail panels were intentionally left standalone and deferred for consolidation.

Left stack (unchanged this slice): Village Status, Tinyfolk Raid HUD, Labor Job HUD, Tinyfolk Inspect (bottom-left).

## Slice boundary (slice 1 — collapsible accordion)

### In scope

1. New `GiantHudStackClient` (or equivalent) owning one right-column `ScreenGui`
2. Sections for: Treasury, Pen Rationing, Social Economy, Giant Effects — each with collapsed summary row + expand toggle
3. Reuse existing `*Presentation` modules; adapt existing clients as section renderers or inline into stack client
4. Live attribute hooks preserved per section (same attrs as today)
5. Fix vertical overlap — stack sections with computed Y offsets or `UIListLayout`
6. Giant-role gating unchanged (realm-owner / projection checks per panel)
7. Bounded `docs/SYSTEM_BOUNDARIES.md` note

### Out of scope

- Village Status left panel changes
- Tinyfolk-facing HUD changes
- New simulation fields or server projection changes
- Final visual polish, animations, persisted collapse state
- TIN-83 dual-scale camera layout tuning (coordinate but don't block)
- Merging Village Status into right stack

## Architecture (recommended: Option A — accordion)

```
GiantHudStackClient (single ScreenGui, anchor 0.98 right)
  ├── Section: Treasury      → GiantRealmTreasuryPresentation
  ├── Section: Pen Rationing → PenRationingHudPresentation
  ├── Section: Social Economy → SocialEconomyPresentation
  └── Section: Giant Effects  → (existing effect presentation)
Each section: collapsed summary + expand/collapse; attribute hooks → refresh section model
```

Retire standalone right-edge `ScreenGui` creation from migrated clients (destroy-on-load pattern replaced by stack ownership).

## Key files

| Path | Purpose |
|------|---------|
| `src/StarterPlayer/StarterPlayerScripts/Client/GiantHudStackClient.client.luau` | New stack owner (proposed) |
| `src/StarterPlayer/StarterPlayerScripts/Client/GiantTreasuryHudClient.client.luau` | Migrate or retire |
| `src/StarterPlayer/StarterPlayerScripts/Client/PenRationingHudClient.client.luau` | Migrate or retire |
| `src/StarterPlayer/StarterPlayerScripts/Client/SocialEconomyHudClient.client.luau` | Migrate or retire |
| `src/StarterPlayer/StarterPlayerScripts/Client/GiantEffectHudClient.client.luau` | Migrate or retire |
| `src/ReplicatedStorage/Shared/GiantRealm/*Presentation.luau` | Unchanged presentation logic |
| `src/ReplicatedStorage/Shared/Config/*HudConfig.luau` | Unchanged attribute registries |
| `docs/SYSTEM_BOUNDARIES.md` | HUD consolidation status note |

## Validation

```powershell
.\scripts\run-validation.ps1 -ChangedOnly
.\scripts\run-tests.ps1
```

Studio (Giant role, realm owner):

- No overlapping right-stack panels
- Each section shows collapsed summary when data projected
- Expand section → full detail visible; collapse → summary only
- Treasury / pen / social / effect attribute changes update live while expanded and collapsed
- Village Status left panel unaffected
- Tinyfolk Inspect bottom-left unaffected

## Acceptance criteria

| Criterion | Approach |
|-----------|----------|
| No overlap | Single stack with layout-driven spacing |
| Live updates | Attribute hooks per section preserved |
| Expand/collapse | Functional toggle per section |
| Left anchor unchanged | Village Status client untouched |
| No double-render | One ScreenGui; old clients retired or no-op |

## Session workflow

1. Move TIN-252 → **In Progress** in Linear
2. Branch: `tin-252-consolidate-giant-hud-right-stack-panels` from `master`
3. Implement: stack shell → migrate first section (Treasury) → remaining sections → remove duplicate GUIs → Studio pass → ship loop

## Risks

- Five independent clients today each create/destroy their own `ScreenGui` — migration order matters to avoid double-render during transition
- Z-index and anchor drift if sections use mixed positioning styles
- Do after TIN-250 (inspect highlight) so bottom-left layout is stable

## Deferred follow-ups

- Unified theming and animation
- Persist collapse state across sessions
- Merge redundant summaries already shown in Village Status
- Mobile / gamepad layout pass
