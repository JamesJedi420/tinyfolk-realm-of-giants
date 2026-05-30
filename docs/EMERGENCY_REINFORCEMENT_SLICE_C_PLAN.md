# Emergency Reinforcement Slice C Integration Plan

## Scope
Slice C wires EmergencyReinforcementService to objective-token consumption for the call-center trigger without breaking current system boundaries.

## Goal
Define a deterministic handshake for objective token consumption and make ownership boundaries explicit before any service-to-objective mutation is introduced.

## Ownership Boundaries
- EmergencyReinforcementService owns request ingress, eligibility gating, one-time call state, and reinforcement spawn/init orchestration.
- Objective system owns objective token state and mutation authority.
- EmergencyReinforcementService must not mutate objective token state directly.
- Objective system must not own reinforcement candidate selection or spawn placement.

## Handshake Contract (Implemented)
1. Reinforcement service validates requester/alive/cooldown and local objective payload/range.
2. Reinforcement service evaluates deterministic reinforcement state transition inputs (threshold/readiness/one-time-use).
3. If transition rejects, request rejects with transition-owned reason and no objective token mutation is attempted.
4. If transition accepts, service calls objective token lifecycle and consume seams in order:
  - GetEmergencyTokenSnapshot(objectiveId, at)
  - RequestConsumeEmergencyToken(requesterUserId, objectiveId, at)
5. Objective seam returns deterministic result:
  - accepted: boolean
  - reason: string
  - tokenState: optional snapshot
6. If snapshot or consume rejects/faults, reinforcement request rejects with deterministic token reason and one-time-use state remains unconsumed.
7. If token consume accepts, reinforcement service proceeds with spawn/init flow; spawn failure returns deterministic compensation trace fields for reconciliation.

## Required Query/Mutation Seams
- _RealmObjectiveService_QueryAPI.RequestConsumeEmergencyToken(...)
- _RealmObjectiveService_QueryAPI.GetEmergencyTokenSnapshot(objectiveId)

## Deterministic Reason Ordering
Reinforcement service preserves this ordering:
1. requester_not_found / requester_user_id_invalid
2. requester_not_alive
3. request_cooldown
4. local objective payload validity and objective range
5. state transition readiness gates and one-time-use checks
6. objective token snapshot + consume lifecycle gates
7. spawn initialization and compensation-trace handling

## Slice C Test Plan
- Runtime tests:
  - token snapshot rejected/faulted -> reinforcement rejected, token reason preserved
  - token consume rejected/faulted -> reinforcement rejected, token reason preserved
  - token consume accepted + transition accepted -> reinforcement accepted
  - token consume accepted + spawn failure -> deterministic failure reason and compensation trace field
- Contract tests:
  - response payload shape unchanged for request/query paths
  - readiness precedence still deterministic
- Regression gate:
  - emergency_reinforcement_state.spec.luau
  - emergency_reinforcement_service_runtime_entrypoint.spec.luau
  - escape_service_runtime_entrypoint.spec.luau
  - headless_match_simulation.spec.luau
  - final_exit_state.spec.luau

## Regression Gate Wiring Status
- The default scripted suite (`scripts/run-tests.ps1`) now includes both `tests/escape_service_runtime_entrypoint.spec.luau` and `tests/final_exit_state.spec.luau` so Slice C regression checks run in baseline CI-style local validation.

## Out of Scope (Slice C)
- HUD/icon/countdown presentation
- multi-reinforcement variants
- persistence of reinforcement call state
