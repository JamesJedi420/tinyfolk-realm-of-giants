# TIN-252 Consolidate Giant HUD Right-Stack Panels — Closure

**Date:** 2026-06-19  
**Issue:** [TIN-252](https://linear.app/spectranoir/issue/TIN-252/consolidate-giant-hud-right-stack-panels)  
**PR:** https://github.com/JamesJedi420/tinyfolk-realm-of-giants/pull/146

## Shipped

- `GiantHudStackConfig` — stack layout constants and legacy GUI names.
- `GiantHudStackClient` — single right-column accordion with Treasury, Pen Rationing, Social Economy, and Giant Effects sections (collapsed summary + expand/collapse toggle).
- Reuses existing `*Presentation` modules; preserves attribute hooks (including pen part attrs).
- Retired standalone clients: `GiantTreasuryHudClient`, `PenRationingHudClient`, `SocialEconomyHudClient`, `GiantEffectHudClient`.
- `docs/SYSTEM_BOUNDARIES.md` updated.

## Validation (automated)

```powershell
lune run tests/pen_rationing_hud_presentation.spec.luau
lune run tests/giant_effect_hud_presentation.spec.luau
.\scripts\run-validation.ps1 -ChangedOnly
.\scripts\run-tests.ps1
```

- CI Validate and test on PR #146 — **PASS**
- Merge commit: `793b3565`

## Studio smoke

**Status: PENDING** — tracked in [TIN-252 Studio evidence](TIN-252_CONSOLIDATE_GIANT_HUD_RIGHT_STACK_STUDIO_EVIDENCE_2026-06-19.md).

Do not mark this slice fully playtest-verified until the evidence table is updated to PASS.

## Deferred

- Persisted collapse state across sessions
- Unified theming and animation
- Deduplicate summaries already shown in Village Status
- Mobile / gamepad layout pass
