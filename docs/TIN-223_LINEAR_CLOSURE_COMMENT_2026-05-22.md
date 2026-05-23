TIN-223 closure update (Tinyfolk scope only)

Validated and closed the bounded Giant staged threat progression slice.

Completed scope:
- Confirmed deterministic shared staged-threat logic (`calm/watch/pressure/critical`) with warning-level promotion and one-step decay over hold windows.
- Confirmed runtime integration in Tinyfolk status service projects staged threat via the existing raid HUD attribute surface.
- Kept the slice bounded: coarse pressure progression only, with no exact tracking and no automatic capture outcomes.

Validation:
- PASSED full listed suite via `./scripts/run-tests.ps1` (captured in `test_output_tin223_preclosure.txt`).
- PASSED `tests/giant_threat_stage_logic.spec.luau`.
- PASSED `tests/tinyfolk_status_service_runtime_entrypoint.spec.luau`.
- Evidence markers include:
  - `PASS [calm stage is default]`
  - `PASS [raid threat stage reflects nearby giant pressure]`
  - `PASS [raid threat stage decays one step at a time]`

Evidence and docs:
- Closure record: `docs/TIN-223_GIANT_THREAT_STAGE_CLOSURE_2026-05-22.md`
- Boundary pointer updated: `docs/SYSTEM_BOUNDARIES.md`
- Evidence log: `test_output_tin223_preclosure.txt`

Commit anchor:
- `10438969` Add snare traps and giant threat stages

Pre-closure checks:
1. Implementation gaps: none identified inside bounded staged-threat scope.
2. Validation/evidence strength: targeted + full listed-suite evidence captured.
3. Required document updates: closure doc and system-boundaries pointer added.
4. Boundary/dependencies: no exact tracking, no automatic capture behavior, no expanded late-game lock mechanics.
5. Remaining cleanup: no new dead code/TODOs introduced in closure prep.

Ready for Done.
