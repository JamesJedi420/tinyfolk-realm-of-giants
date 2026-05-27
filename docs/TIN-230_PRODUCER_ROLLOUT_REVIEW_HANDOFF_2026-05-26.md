# TIN-230 Producer Rollout Review Handoff (2026-05-26)

## Issue
- ID: TIN-230
- Title: Producer rollout #2 on non-rescue ingress using AdmissionQueueProducer
- Status decision: make this the active Tinyfolk issue and move it to review.
- Branch/PR: master (local-only)

## Summary
- TIN-230 is the current active Tinyfolk issue because local HEAD already contains the bounded non-rescue producer rollout work.
- The party matchmaking admission ingress now routes through `AdmissionQueueProducer`, preserving shared enqueue payload and failure-reason semantics.
- The prerequisite TIN-229 resolver seam is implemented locally and covered by focused runtime specs, so it should be treated as review/closure cleanup rather than the next implementation issue.
- The latest handoff enqueue edge validation hardens the transfer handoff path without broadening into all-ingress rollout, scheduler tuning, or observability dashboard work.

## Implementation Evidence
- `PartyMatchmakingAdmissionService` resolves target realm context through the party matchmaking resolver seam when available, falls back only to explicit target realm input, and rejects unavailable/rejected resolver results without enqueue side effects.
- `AdmissionQueueProducer` owns shared payload normalization for operation id, party id, target realm id, entry type, member user ids, timestamps, expiration, retry count, and queue failure handling.
- `ProfileTeleportHandoffService` now validates target realm input and admission enqueue failures deterministically before leaving handoff state pending.

## Validation Evidence
- `lune run tests/party_matchmaking_admission_service_runtime_entrypoint.spec.luau` -> all checks passed.
- `lune run tests/party_matchmaking_realm_resolver_service_runtime_entrypoint.spec.luau` -> all checks passed.
- `lune run tests/profile_teleport_handoff_service_runtime_entrypoint.spec.luau` -> all checks passed.

## Boundary Notes
- Included: one additional non-rescue ingress using `AdmissionQueueProducer`, deterministic resolver handling, enqueue rejection propagation, and no-partial-success behavior.
- Out of scope: full all-ingress rollout, scheduler tuning, observability dashboards, and published-client teleport evidence.

## Final Decision
- Recommended Linear state: In Review.
- Basis: implementation is present locally, focused validation is green, and the remaining work is review/closure reconciliation rather than new implementation.
