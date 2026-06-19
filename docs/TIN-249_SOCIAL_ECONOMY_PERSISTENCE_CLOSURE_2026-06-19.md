# TIN-249 Social Economy Persistence — Closure

**Date:** 2026-06-19  
**Issue:** [TIN-249](https://linear.app/spectranoir/issue/TIN-249/persist-social-economy-on-giant-realm-save-root)  
**Parent:** [TIN-28](https://linear.app/spectranoir/issue/TIN-28/implement-social-economy-layer)

## Shipped

- `socialEconomyPersistence` optional block on `GiantRealmSaveSchema.GiantRealmSaveRoot` (favor, control, recentEvents).
- `SocialEconomyState` persistence helpers: `ValidateEventRecord`, `SerializePersistenceState`, `ApplyPersistenceState`.
- `EventStateOwnershipModel` namespace registration: `socialEconomyPersistence → realm_profile`.
- `SocialEconomyService` `BuildPersistenceState` / `ApplyPersistenceState` on `_SocialEconomyService_QueryAPI`.
- `GiantBuildModeService` build/apply snapshot wiring for social economy persistence.
- Focused specs for state, schema, ownership model, service runtime, and build-mode snapshot integration.

## Validation

```powershell
lune run tests/social_economy_state.spec.luau
lune run tests/giant_realm_save_schema.spec.luau
lune run tests/event_state_ownership_model.spec.luau
lune run tests/social_economy_service_runtime_entrypoint.spec.luau
lune run tests/giant_build_mode_service_runtime_entrypoint.spec.luau
.\scripts\run-validation.ps1 -ChangedOnly
.\scripts\run-tests.ps1
```

## Deferred

- Per-Tinyfolk dyadic favor/fear maps, decay/caps balancing, gameplay modifier consumers, HUD polish.
- Full operation-id dedup ledger beyond retained `recentEvents` window (same limitation as giant reputation).
