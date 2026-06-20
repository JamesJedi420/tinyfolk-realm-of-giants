# TIN-256 Treasury Metal HUD Projection — Closure

**Date:** 2026-06-20  
**Issue:** [TIN-256](https://linear.app/spectranoir/issue/TIN-256/project-session-metal-into-giant-treasury-hud)

## Shipped

- `GiantRealmTreasuryPresentation` — `sessionMetal` field and `Session … M…` summary format.
- `GiantRealmTreasuryConfig.SessionMetal` attribute.
- `GiantBuildModeService.buildSessionTreasurySnapshot` reads `Metal.stored`; fixed W/S to use lowercase `stored`.
- `RefreshTreasuryProjection` query API seam; `WarehousingService` refreshes treasury after deliveries.
- `GiantHudStackClient` collects and passes `SessionMetal`.
- Tests extended in `tests/giant_realm_treasury_presentation.spec.luau`.
- `docs/SYSTEM_BOUNDARIES.md` updated.

## Validation (automated)

```powershell
lune run tests/giant_realm_treasury_presentation.spec.luau
.\scripts\run-validation.ps1 -ChangedOnly
```

## Studio smoke

**Status: PENDING** — tracked in [TIN-256 Studio evidence](TIN-256_TREASURY_METAL_HUD_PROJECTION_STUDIO_EVIDENCE_2026-06-20.md).

## Deferred

- Ledger Metal and construction metal spend (TIN-27)
- Giant HUD polish (TIN-252 deferred)
