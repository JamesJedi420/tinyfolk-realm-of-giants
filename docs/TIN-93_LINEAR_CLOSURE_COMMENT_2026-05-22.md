TIN-93 closure update (Tinyfolk scope only)

Implemented and validated the bounded event-log slice.

Completed scope:
- Added shared config for event-log limits/severity defaults.
- Added deterministic shared event-log state with strict validation for timestamp/category/message/severity.
- Added runtime EventLog service seam for game-system emission and debug/query access (RecordEvent, RecordEventFromPayload, GetRecentEvents, GetStateSnapshot, ResetForTests).
- Added focused tests for shared-state behavior and runtime service behavior.
- Added both event-log tests to the explicit scripts/run-tests.ps1 list.

Validation:
- PASSED tests/event_log_state.spec.luau
- PASSED tests/event_log_service_runtime_entrypoint.spec.luau
- PASSED ./scripts/run-tests.ps1 with event-log markers present in committed evidence output

Evidence and docs:
- Closure record: docs/TIN-93_EVENT_LOG_CLOSURE_2026-05-22.md
- Boundary pointer updated: docs/SYSTEM_BOUNDARIES.md
- Committed evidence log: test_output_tin93_eventlog.txt

Commits:
- 2b858db6 TIN-93: add event log state/service and test coverage
- 4c220718 TIN-93: add event-log verification output checkpoint

Pre-closure checks:
1. Implementation gaps: none identified inside bounded event-log scope.
2. Validation/evidence strength: focused tests + listed-suite evidence captured.
3. Required document updates: closure doc and system-boundaries pointer added.
4. Boundary/dependencies: no persistence or analytics expansion; runtime/debug surface only.
5. Remaining cleanup: no dead code/TODOs introduced in this closure prep.

Ready for Done.
