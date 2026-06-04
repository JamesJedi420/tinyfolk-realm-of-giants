# TIN-173 Realm Chunk Assembly Schema Slice B

Date: 2026-06-04

This slice hardens deterministic realm chunk assembly integrity for the prototype contract.

- `AuthoredChunk` now requires chunk-level `validatorMetadata` using `ChunkValidatorMetadata`.
- `ValidateAssemblyInputContract` validates assembly and chunk validator metadata, plus structural metadata enum fields for tile size, environment, and traversal density.
- `BuildAssemblyOutput` treats socket world-position mismatch, non-opposing socket forward vectors, and disconnected placements as blocking assembly integrity issues.
- Blocking assembly failures remain inspectable through `integrity.issues` and `validatorHandoff.blockingAssemblyIssueCodes`; `descriptorReady` stays false when assembly integrity fails.
- `RealmAssemblyPrototypeFixture` includes validator metadata and small invalid fixture helpers for misaligned, misoriented, and disconnected assemblies.

Validation targets:

- `lune run tests/realm_chunk_assembly_schema.spec.luau`
- `lune run tests/district_placement_assembly_selection_runtime_entrypoint.spec.luau`
- `./scripts/run-validation.ps1 -ChangedOnly`
