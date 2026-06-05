# TIN-173 Realm Chunk Assembly Schema Slice C

Date: 2026-06-05

This slice adds bounded route/transition metadata handoff for authored chunks.

- `AuthoredChunk.routeTransitions` can declare per-chunk transition metadata by socket reference.
- Transition metadata stays schema-level only: transition kind/role enums, optional tags, and socket references are validated deterministically.
- `ValidateAssemblyInputContract` rejects malformed transition arrays, invalid enum fields, duplicate transition ids, duplicate transition tags, and transitions pointing at missing chunk sockets.
- `BuildAssemblyOutput` preserves transition metadata in `resolvedRouteTransitions`, `resolvedRouteTransitionsByPlacement`, and `validatorHandoff.routeTransitions` / `routeTransitionsByPlacement` so downstream validators can inspect it without changing topology validation behavior.
- `RealmAssemblyPrototypeFixture` includes valid transition metadata plus invalid fixture helpers for focused schema coverage.

Out of scope:

- Authoring tools, procedural generation, map-specific route layout logic, topology balancing heuristics, and map/station file edits.

Validation targets:

- `lune run tests/realm_chunk_assembly_schema.spec.luau`
- `lune run tests/district_placement_assembly_selection_runtime_entrypoint.spec.luau`
- `rojo build default.project.json -o TinyfolkRealmOfGiants.rbxlx`
- `powershell -NoProfile -ExecutionPolicy Bypass -File ./scripts/run-validation.ps1 -ChangedOnly`
