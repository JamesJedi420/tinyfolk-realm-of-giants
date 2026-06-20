# TIN-253 Loyalty-tone Inspect Selection Highlight — Closure

**Date:** 2026-06-20  
**Issue:** [TIN-253](https://linear.app/spectranoir/issue/TIN-253/loyalty-tone-inspect-selection-highlight)

## Shipped

- `TinyfolkInspectState.ResolveHighlightTone` — custody non-neutral wins; dyadic dominant axis maps favor → `positive`, control → `warning`, balanced → `neutral`.
- `TinyfolkInspectConfig.Tones.Positive` and `HighlightAccentRgbByTone` for highlight colors.
- `TinyfolkInspectClient` — highlight uses `ResolveHighlightTone`; panel accent remains custody `ResolveTone`.
- Tests extended in `tests/tinyfolk_inspect_state.spec.luau`.
- `docs/SYSTEM_BOUNDARIES.md` updated.

## Validation (automated)

```powershell
lune run tests/tinyfolk_inspect_state.spec.luau
lune run tests/tinyfolk_inspect_presentation.spec.luau
.\scripts\run-validation.ps1 -ChangedOnly
```

- Local lune inspect specs panic on Windows lune 0.10.1 (`Enum` in config) — pre-existing; CI Linux suite is source of truth.

## Studio smoke

**Status: PENDING** — tracked in [TIN-253 Studio evidence](TIN-253_LOYALTY_TONE_INSPECT_HIGHLIGHT_STUDIO_EVIDENCE_2026-06-20.md).

## Deferred

- Gameplay consumers of dyadic attrs
- Per-Tinyfolk morale simulation
