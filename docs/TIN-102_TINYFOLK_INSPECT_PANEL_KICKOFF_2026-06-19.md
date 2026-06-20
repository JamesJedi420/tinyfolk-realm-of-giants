# TIN-102 Tinyfolk Inspect Panel Kickoff (2026-06-19)

## Issue

- ID: TIN-102
- Title: Implement Tinyfolk inspect panel
- Linear: https://linear.app/spectranoir/issue/TIN-102/implement-tinyfolk-inspect-panel
- Milestone: Threat Progression and HUD

## Goal

Let Giants inspect individual Tinyfolk via mouse click selection. Read replicated per-player attributes through a Shared Config/State/Presentation triplet and a client panel that updates live.

## Context

TIN-92 adds village-wide Giant HUD; TIN-102 adds per-Tinyfolk detail on click. No character selection exists today. Per-player state (custody, jobs, score, sprint stamina, pen stress) already replicates on player attributes.

## Slice boundary (slice 1)

### In scope

1. Giant-only click selection (camera raycast on Tinyfolk character)
2. `TinyfolkInspectConfig`, `TinyfolkInspectState`, `TinyfolkInspectPresentation`
3. `TinyfolkInspectClient` — bottom-left panel, attribute hooks on selected target
4. Pure tests for state and presentation
5. `docs/SYSTEM_BOUNDARIES.md` bounded note

### Out of scope

- Tinyfolk or cross-role inspect viewers
- New morale / loyalty / fatigue / trait simulation
- Server projection or inspect remotes
- Selection highlight / VFX polish
- InteractionResolver / F-key integration
- Persistence changes

## Field mapping

| Issue field | Slice 1 source | Notes |
|-------------|----------------|-------|
| Name | `Player.DisplayName` | Title |
| Role | `Role`, `SpecialistRole` | Role line |
| Traits | `SpecialistRole`, `TinyfolkTrait_PostCrossingBurst` | Comma-separated or `None` |
| Morale | Pen captive stress attrs; fear/threat for raiders | Labeled proxy; no fabricated per-Tinyfolk morale sim |
| Fatigue | `TinyfolkSprintStaminaRatio`, `TinyfolkSprintExhausted` | `—` when absent |
| Loyalty | — | `Unavailable` (TIN-28 dyadic maps deferred) |
| Assignment | `TinyfolkScheduledJob*` + haul attrs | Reuses labor job label patterns |
| Value | `ScoreTotal`, `TinyfolkLaborTokens` | Score + tokens |

Custody bonus line: capture, carry, downed from existing attrs.

## Architecture

```
Mouse click → raycast → selected Tinyfolk
  → TinyfolkInspectState.BuildSnapshot(attrs)
  → TinyfolkInspectPresentation.BuildPanelModel(snapshot)
  → TinyfolkInspectClient panel
Target GetAttributeChangedSignal → refresh
```

No new server service in slice 1.

## Key files (new)

| Path | Purpose |
|------|---------|
| `src/ReplicatedStorage/Shared/Config/TinyfolkInspectConfig.luau` | Range, GUI names, attribute registry |
| `src/ReplicatedStorage/Shared/GiantRealm/TinyfolkInspectState.luau` | Pure snapshot + tone |
| `src/ReplicatedStorage/Shared/GiantRealm/TinyfolkInspectPresentation.luau` | Pure panel model |
| `src/StarterPlayer/StarterPlayerScripts/Client/TinyfolkInspectClient.client.luau` | Selection + panel |
| `tests/tinyfolk_inspect_state.spec.luau` | State tests |
| `tests/tinyfolk_inspect_presentation.spec.luau` | Presentation tests |

## Validation

```powershell
lune run tests/tinyfolk_inspect_state.spec.luau
lune run tests/tinyfolk_inspect_presentation.spec.luau
.\scripts\run-validation.ps1 -ChangedOnly
.\scripts\run-tests.ps1
```

Studio:

- Giant → click Tinyfolk → panel opens with all issue fields
- Click empty → panel closes
- Capture/carry/downed → custody + tone update live
- Captive pen stress → morale line updates
- Loyalty shows `Unavailable`

## Acceptance criteria

| Criterion | Approach |
|-----------|----------|
| Selecting Tinyfolk opens panel | Raycast click, in-range Tinyfolk |
| Displays current state | All eight fields (loyalty unavailable) |
| Updates on change | Target attribute hooks |
| Placeholder visual design | Village Status HUD shell pattern |

## Deferred follow-ups

- Per-Tinyfolk loyalty/morale simulation
- Selection highlight
- Tinyfolk teammate inspect
- Keyboard / gamepad fallback
- Server-curated inspect snapshot
