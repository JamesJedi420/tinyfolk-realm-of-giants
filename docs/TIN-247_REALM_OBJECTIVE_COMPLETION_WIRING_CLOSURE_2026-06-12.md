# TIN-247 Realm Objective Completion Wiring Closure (2026-06-12)

## Issue

- ID: TIN-247
- Title: Wire realm objective completion from contextual task runtimes
- Date: 2026-06-12

## Shipped

- Added `RealmObjectiveSiteIdResolver` to map contextual task site ids to registered objective site ids (`ConstructionSite_*` direct; `WorkStation_*` → `ObjectiveSite_Workyard`; `MiningStation_*` → `ObjectiveSite_Quarry`; `Shrine_*` → `ObjectiveSite_Shrine`).
- Added `RealmObjectiveCompletionCaller` bridging contextual completions to `_RealmObjectiveService_QueryAPI.RecordObjectiveCompletion`.
- Wired completion caller from bounded contextual-task `complete` paths in `ConstructionService`, `StationService`, and `ShrineService` after successful build/work-action completion.
- Extended runtime entrypoint specs for construction, station, and shrine services; added `realm_objective_site_id_resolver.spec.luau`.

## Boundary

- Completion wiring only — no unlock/XP producer semantic changes.
- One `RecordObjectiveCompletion` call per accepted contextual-task completion; idempotency remains owned by `RealmObjectiveState.RecordCompletion`.
- Legacy (non-task) construction/station/shrine paths unchanged.

## Validation

```powershell
.\scripts\run-validation.ps1 -ChangedOnly
lune run tests/realm_objective_site_id_resolver.spec.luau
lune run tests/construction_service_runtime_entrypoint.spec.luau
lune run tests/station_service_runtime_entrypoint.spec.luau
lune run tests/shrine_service_runtime_entrypoint.spec.luau
.\scripts\run-tests.ps1
```

## Deferred

- Studio spot-check for TIN-149 collision matrix.
- TIN-150 physics ownership for capture/escape/custody assemblies.
