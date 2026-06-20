# TIN-250 Tinyfolk Inspect Selection Highlight Kickoff (2026-06-19)

## Issue

- ID: TIN-250
- Title: Tinyfolk inspect selection highlight
- Linear: https://linear.app/spectranoir/issue/TIN-250/tinyfolk-inspect-selection-highlight
- Milestone: Threat Progression and HUD
- Related: [TIN-102](https://linear.app/spectranoir/issue/TIN-102/implement-tinyfolk-inspect-panel)

## Goal

When a Giant click-selects a Tinyfolk for inspect, show a clear world-space selection highlight on the chosen character so selection is obvious beyond the bottom-left inspect panel.

## Context

TIN-102 ships Giant-only click selection, attribute-driven inspect panel, and live refresh on custody/tone changes. Selection highlight was explicitly deferred as client-only polish. No server projection or remotes are required.

## Slice boundary

### In scope

1. `Highlight` instance (preferred) on selected Tinyfolk character in `TinyfolkInspectClient`
2. Highlight color driven by inspect panel tone (`neutral` / `warning` / `critical`) — reuse `ACCENT_BY_TONE` mapping
3. Lifecycle tied to existing `hookTarget` / `clearSelection` / `refreshPanel` seams
4. Optional highlight constants in `TinyfolkInspectConfig` (fill/outline transparency, depth mode)
5. Bounded `docs/SYSTEM_BOUNDARIES.md` note under TIN-102 inspect entry

### Out of scope

- Server changes, remotes, or new simulation
- Hover preview, multi-select, keyboard/gamepad selection
- InteractionResolver / F-key integration
- Name billboard (optional follow-up; labor-job billboard may already target same Tinyfolk)
- Shared/pure modules unless config extraction is needed

## Architecture

```
Mouse click → raycast → selected Tinyfolk (existing TIN-102)
  → hookTarget → apply Highlight on character
  → refreshPanel → update Highlight fill/outline from snapshot tone
  → clearSelection → destroy Highlight
CharacterRemoving / out-of-range / empty click → clearSelection
```

No new server service. Client-only extension of `TinyfolkInspectClient`.

## Key files

| Path | Purpose |
|------|---------|
| `src/StarterPlayer/StarterPlayerScripts/Client/TinyfolkInspectClient.client.luau` | Highlight create/update/destroy on selection lifecycle |
| `src/ReplicatedStorage/Shared/Config/TinyfolkInspectConfig.luau` | Optional highlight color/transparency constants |
| `docs/SYSTEM_BOUNDARIES.md` | Bounded status note |

Reference (billboard lifecycle pattern, not required for slice):

| Path | Purpose |
|------|---------|
| `src/StarterPlayer/StarterPlayerScripts/Client/TinyfolkLaborJobHudClient.client.luau` | `applyBillboard` / `clearBillboard` adornee lifecycle |

## Validation

```powershell
.\scripts\run-validation.ps1 -ChangedOnly
.\scripts\run-tests.ps1
```

Studio:

- Giant → click Tinyfolk → highlight visible on character
- Click empty → highlight cleared, panel closed
- Walk out of range → highlight cleared
- Target character respawns / leaves → highlight cleared
- Capture/carry/downed → highlight color matches panel accent tone
- Re-select same or different Tinyfolk → no duplicate Highlight instances

## Acceptance criteria

| Criterion | Approach |
|-----------|----------|
| Selection visible in world | `Highlight` on target character while selected |
| Cleared on deselect | `clearSelection` destroys highlight |
| Tone sync | `refreshPanel` updates highlight color from snapshot tone |
| No leak / duplicate | Single highlight instance; destroy before recreate |

## Session workflow

1. Move TIN-250 → **In Progress** in Linear
2. Branch: `tin-250-tinyfolk-inspect-selection-highlight` from `master`
3. Implement: config constants (if needed) → client highlight lifecycle → Studio pass → audit → ship loop per `.cursor/rules/pr-ship-workflow.mdc`

## Deferred follow-ups

- Hover highlight before click
- Optional name billboard above selected Tinyfolk
- Selection ring at feet / ground marker
- Gamepad cursor target highlight
