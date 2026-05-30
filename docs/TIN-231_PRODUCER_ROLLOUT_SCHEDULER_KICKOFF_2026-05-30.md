# TIN-231 Producer Rollout + Scheduler Refinement Kickoff (2026-05-30)

## Issue
- ID: TIN-231
- Title: Broaden AdmissionQueueProducer rollout and scheduler refinement
- Linear: https://linear.app/spectranoir/issue/TIN-231/broaden-admissionqueueproducer-rollout-and-scheduler-refinement
- Status: Backlog

## Why This Slice Exists
- TIN-230 closed the bounded second producer rollout on one non-rescue ingress.
- Deferred scope remains for broader producer ingress parity and operational scheduler hardening.
- This kickoff records a bounded implementation plan before code changes begin.

## Proposed Bounded Scope
- Add AdmissionQueueProducer integration to additional non-rescue ingress paths that still use direct enqueue behavior.
- Add explicit scheduler tuning seam for admission queue processing cadence and batch size, with conservative defaults.
- Add lightweight observability surface for processor outcomes (`retryDeferred`, terminal outcomes, and bounded failure reasons).
- Preserve existing deterministic failure-reason contracts and avoid broad queue architecture rewrites.

## Out of Scope
- Full observability dashboards or external telemetry platform integration.
- Unbounded all-ingress migration in a single pass.
- Any change that couples gameplay systems directly to raw MemoryStore primitives.

## Initial Implementation Plan
1. Enumerate all remaining ingress paths that enqueue admission operations and classify by current producer usage.
2. Select a small first batch of non-rescue ingress targets and migrate to AdmissionQueueProducer with parity tests.
3. Introduce scheduler config seam for interval/batch with strict validation and bounded defaults.
4. Add deterministic query/debug snapshot for processor counters and per-run outcomes.
5. Extend focused runtime tests for each migrated ingress and scheduler/observability seam behavior.
6. Run changed-file validation and targeted runtime specs.

## Validation Expectations
- `scripts/run-validation.ps1 -ChangedOnly`
- Focused runtime entrypoint specs for each migrated ingress seam.
- Admission queue processor/service coverage for scheduler configuration and outcome counters.

## Risks and Controls
- Risk: Producer migration changes failure semantics.
  - Control: lock expected reason taxonomy in spec assertions before and after migration.
- Risk: Scheduler tuning causes throughput/regression imbalance.
  - Control: bounded defaults, validated ranges, and deterministic tests around process cadence semantics.
- Risk: Observability seam leaks mutable state.
  - Control: return cloned, read-only snapshots only.

## Exit Criteria (for TIN-231 closure)
- At least one additional non-rescue ingress is migrated with deterministic parity evidence.
- Scheduler config seam is implemented, validated, and tested.
- Lightweight processor observability seam is implemented and tested.
- Boundary docs and closure checklist are updated with explicit in-scope/out-of-scope coverage.
