# TIN-253 Loyalty-tone Inspect Selection Highlight Kickoff (2026-06-20)

## Issue

- ID: TIN-253
- Title: Loyalty-tone inspect selection highlight
- Linear: https://linear.app/spectranoir/issue/TIN-253/loyalty-tone-inspect-selection-highlight
- Milestone: Threat Progression and HUD
- Related: TIN-250, TIN-251, TIN-102

## Goal

When a Giant selects a Tinyfolk with projected dyadic favor/control, the world-space `Highlight` reflects loyalty axis tone. Panel accent remains custody-only (`ResolveTone`).

## Slice boundary

### In scope

1. `TinyfolkInspectState.ResolveHighlightTone` — custody non-neutral wins; else dyadic dominant axis mapping
2. `TinyfolkInspectConfig` — `positive` tone + `HighlightAccentRgbByTone`
3. `TinyfolkInspectClient` — highlight uses `ResolveHighlightTone`; panel accent unchanged
4. Pure tests + `SYSTEM_BOUNDARIES.md` note
5. Studio evidence doc (PENDING rows)

### Out of scope

- Server projection changes
- Panel loyalty line / custody tone changes
- Hover highlight, billboards, gamepad selection

## Validation

```powershell
lune run tests/tinyfolk_inspect_state.spec.luau
lune run tests/tinyfolk_inspect_presentation.spec.luau
.\scripts\run-validation.ps1 -ChangedOnly
```

## Deferred follow-ups

- Gameplay consumers of dyadic attrs (job scheduling bias)
- Per-Tinyfolk morale simulation
