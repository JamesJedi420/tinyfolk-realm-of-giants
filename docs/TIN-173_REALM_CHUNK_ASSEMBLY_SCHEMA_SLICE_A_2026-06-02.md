# TIN-173 Realm Chunk Assembly Schema Slice A (2026-06-02)

## Scope
- Add a bounded assembly input contract for chunk assembly schema/model handoff.
- Keep runtime behavior deterministic and compatibility-safe for existing assembly output consumers.
- Prove contract behavior with focused tests and keep docs aligned with the system boundary.

## Implemented
- Added `ValidateAssemblyInputContract(input)` to `src/ReplicatedStorage/Shared/RealmAssembly/RealmChunkAssemblySchema.luau`.
- Added deterministic reject reasons for:
  - invalid/missing top-level assembly input tables
  - invalid/empty chunk-library shape
  - invalid chunk record metadata (`chunkId`, `chunkKind`, `authoringVersion`, content route-graph shape)
  - duplicate placement ids
  - placement references to missing chunks
  - invalid transform position/yaw metadata
  - malformed declared connection records
- Integrated contract checks into `src/ServerScriptService/Services/DistrictPlacementService.server.luau` assembly input selection path.
- Added guarded fallback to prototype assembly input when registry/config-selected input fails contract validation.

## Test Coverage
- Extended `tests/realm_chunk_assembly_schema.spec.luau` with slice-A contract checks:
  - prototype fixture passes contract validation
  - duplicate placement ids fail with deterministic reason
  - missing placement chunk reference fails with deterministic reason
  - non-integer yaw transform fails with deterministic reason

## Validation
- Full test and validation evidence run completed in this session before slice start:
  - `./scripts/run-tests.ps1`
  - `./scripts/run-validation.ps1`
- Follow-up targeted run recommended after this slice edit:
  - `lune run tests/realm_chunk_assembly_schema.spec.luau`

## Deferred
- Content authoring workflow/tools for chunk authoring remain deferred.
- Procedural or dynamic runtime chunk generation remains deferred.
- Expanded runtime assembly-selection heuristics remain deferred.
