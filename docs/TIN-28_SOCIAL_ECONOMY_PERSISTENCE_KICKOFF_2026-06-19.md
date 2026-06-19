# TIN-28 Social Economy Persistence — Kickoff

**Date:** 2026-06-19  
**Issue:** [TIN-249](https://linear.app/spectranoir/issue/TIN-249/persist-social-economy-on-giant-realm-save-root)  
**Parent:** [TIN-28](https://linear.app/spectranoir/issue/TIN-28/implement-social-economy-layer) (foundation shipped session-only)  
**Architecture:** [TIN-49](https://linear.app/spectranoir/issue/TIN-49/define-persistent-realm-architecture), [TIN-174](docs/TIN-174_EVENT_STATE_OWNERSHIP_MODEL.md), [PROFILE_OWNERSHIP_DECISION](docs/PROFILE_OWNERSHIP_DECISION.md)

## Goal

Persist realm-scoped favor/control social economy state through the existing giant-realm save pipeline (`BuildSaveSnapshot` / `ApplySaveSnapshot`) so axis values and recent event history survive realm reloads.

## Scope

- Add `socialEconomyPersistence` optional block to `GiantRealmSaveSchema.GiantRealmSaveRoot`.
- Add `SocialEconomyState` persistence helpers: `ValidateEventRecord`, `SerializePersistenceState`, `ApplyPersistenceState`.
- Extend `GiantRealmSaveSchema` with validate/serialize helpers and `BuildSaveRoot` wiring.
- Register `socialEconomyPersistence` namespace ownership in `EventStateOwnershipModel` as `realm_profile`.
- Add `BuildPersistenceState` / `ApplyPersistenceState` to `_SocialEconomyService_QueryAPI`.
- Wire `GiantBuildModeService` build/apply snapshot paths (same seam as `giantReputationPersistence`).
- Re-project realm-owner debug attributes after apply.
- Focused specs for state, schema, ownership model, service runtime, and build-mode snapshot integration.

## Save record shape

```lua
-- GiantRealmSaveRoot.socialEconomyPersistence (optional)
{
    favor: number,       -- clamped 0–100
    control: number,     -- clamped 0–100
    recentEvents: {
        {
            operationId: string,
            eventKind: string,
            favorDelta: number,
            controlDelta: number,
            favorAfter: number,
            controlAfter: number,
            awardedAt: number,
        },
    },
}
```

- Persist `favor`, `control`, `recentEvents` only.
- Rebuild in-memory `operationIds` from `recentEvents` on load (do not persist the map).
- Sort `recentEvents` deterministically on serialize (`awardedAt`, then `operationId`).
- Missing block → defaults (`DefaultFavor` / `DefaultControl`, empty events).

## Boundary

- **Owner partition:** `realm_profile` only — no player-profile writes.
- **Reference pattern:** mirror `GiantReputationState` + `giantReputationPersistence` end-to-end.
- **Parallel systems:** keep separate from `giantReputationPersistence`; shared trophy `operationId` is fine (each system dedupes independently).
- **No TIN-174 write-back changes:** social events are trophy/event-driven realm mutations, not capture/escape/defense/return outcomes.
- **Schema version:** remain at `INITIAL_SCHEMA_VERSION = 1` (optional backward-compatible field).
- **No new save pipeline:** gateway → owner layer → existing snapshot path only.

## Out of scope

- Per-Tinyfolk dyadic favor/fear maps.
- Decay, caps, anti-snowball balancing.
- Gameplay modifier consumption (labor compliance, intimidation gates).
- HUD polish beyond existing debug attributes.
- Merging with `GiantReputationState`.
- Schema migration utilities or version bump.
- Autosave policy changes.

## Key files

| Path | Change |
|------|--------|
| `src/ReplicatedStorage/Shared/GiantRealm/SocialEconomyState.luau` | Serialize/apply/validate persistence |
| `src/ReplicatedStorage/Shared/GiantRealm/GiantRealmSaveSchema.luau` | Types, validate, serialize, `BuildSaveRoot` |
| `src/ReplicatedStorage/Shared/GiantRealm/EventStateOwnershipModel.luau` | Namespace registration |
| `src/ServerScriptService/Services/SocialEconomyService.server.luau` | Build/apply QueryAPI |
| `src/ServerScriptService/Services/GiantBuildModeService.server.luau` | Snapshot wiring |
| `tests/social_economy_state.spec.luau` | Persistence unit tests |
| `tests/giant_realm_save_schema.spec.luau` | Schema integration |
| `tests/event_state_ownership_model.spec.luau` | Owner registration |
| `tests/social_economy_service_runtime_entrypoint.spec.luau` | Apply round-trip |
| `tests/giant_build_mode_service_runtime_entrypoint.spec.luau` | Full snapshot path |

## Implementation order

1. `SocialEconomyState` persistence helpers + unit tests.
2. `GiantRealmSaveSchema` types/validate/serialize + schema tests.
3. `EventStateOwnershipModel` registration + spec.
4. `SocialEconomyService` Build/Apply + runtime spec.
5. `GiantBuildModeService` snapshot wiring + entrypoint spec.
6. Closure doc + optional `SYSTEM_BOUNDARIES` / TIN-174 doc hygiene.

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

## Test scenarios

- Empty/missing save block → defaults on apply.
- Populated save → favor/control/events restored; owner attributes re-projected.
- Duplicate `operationId` in persisted events → validation failure.
- Trophy social event before save → survives build/apply without double-apply.
- `ValidateSaveRoot` accepts valid block; rejects malformed records.
- `EventStateOwnershipModel.GetNamespaceOwner("socialEconomyPersistence") == realm_profile`.

## Risks

| Risk | Mitigation |
|------|------------|
| Idempotency window limited to retained `recentEvents` (max 50) | Same pattern as giant reputation; document in closure |
| `BuildSaveRoot` parameter arity growth | Add param in one slice; update all call sites together |
| Service init / apply ordering | Match giant reputation apply ordering in `ApplySaveSnapshot` |

## Studio follow-up

Record trophy-driven social events as Giant, trigger realm save (leave/shutdown), rejoin realm, confirm `SocialEconomyFavor` / `SocialEconomyControl` attributes match pre-save values.

## Deferred (still TIN-28 long-term)

- Final balancing, gameplay modifier consumers, HUD polish, per-Tinyfolk dyadic maps, covenant/miracle/domain expansion paths.
