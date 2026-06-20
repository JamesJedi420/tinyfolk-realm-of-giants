# TIN-251 Project Dyadic Loyalty to Tinyfolk Inspect — Closure

**Date:** 2026-06-19  
**Issue:** [TIN-251](https://linear.app/spectranoir/issue/TIN-251/project-dyadic-loyalty-to-tinyfolk-inspect)  
**PR:** https://github.com/JamesJedi420/tinyfolk-realm-of-giants/pull/144 (StyLua hotfix: #145)

## Shipped

- `SocialDyadicFavor` / `SocialDyadicControl` attribute projection in `SocialEconomyService`.
- Clear on custody-exit trophy kinds, `PlayerRemoving`, and `CaptureService` custody end.
- `TinyfolkInspectState.ResolveLoyaltyLine` → numeric `Loyalty: Favor N / Control N`.
- Registered attrs in `TinyfolkInspectConfig`; `SYSTEM_BOUNDARIES.md` updated.

## Validation (automated)

```powershell
lune run tests/social_economy_service_runtime_entrypoint.spec.luau
lune run tests/social_economy_state.spec.luau
lune run tests/tinyfolk_inspect_state.spec.luau
lune run tests/tinyfolk_inspect_presentation.spec.luau
.\scripts\run-validation.ps1 -ChangedOnly
```

- Service runtime specs — **PASS** (local + CI post hotfix)
- Merge: `13a97296`; master CI green after #145

## Studio smoke

**Status: PENDING** — tracked in [TIN-251 Studio evidence](TIN-251_PROJECT_DYADIC_LOYALTY_TO_TINYFOLK_INSPECT_STUDIO_EVIDENCE_2026-06-19.md).

## Deferred

- Per-Tinyfolk morale simulation
- Gameplay consumers of per-Tinyfolk dyadic attrs
- Server-curated inspect snapshot
- Loyalty tone on selection highlight
