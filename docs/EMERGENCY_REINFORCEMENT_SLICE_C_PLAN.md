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

## Handshake Contract (Proposed)
1. Reinforcement service validates requester/alive/cooldown and computes candidate readiness inputs.
2. Reinforcement service calls objective query/mutation seam:
   - RequestConsumeEmergencyToken(requesterUserId, objectiveId, at)
3. Objective seam returns deterministic result:
   - accepted: boolean
   - reason: string
   - tokenState: optional snapshot
4. If token consume rejects, reinforcement request rejects with objective-owned reason mapped into service response.
5. If token consume accepts, reinforcement service proceeds with existing Slice A/B reinforcement transition and spawn flow.
6. If reinforcement transition fails after token acceptance, service returns a deterministic compensation-required reason (deferred policy) and emits trace fields for reconciliation.

## Required Query/Mutation Seams
- _RealmObjectiveService_QueryAPI.RequestConsumeEmergencyToken(...)
- _RealmObjectiveService_QueryAPI.GetEmergencyTokenSnapshot(objectiveId)

## Deterministic Reason Ordering
Reinforcement service should preserve current ordering before objective consume:
1. requester_not_found / requester_user_id_invalid
2. requester_not_alive
3. request_cooldown
4. local objective payload validity
5. objective token consume request
6. readiness gates (objective/spawn/protection/candidate)
7. state transition and spawn initialization

## Slice C Test Plan
- Runtime tests:
  - token consume rejected -> reinforcement rejected, token reason preserved
  - token consume accepted + transition accepted -> reinforcement accepted
  - token consume accepted + transition fault -> deterministic failure reason and compensation trace field
- Contract tests:
  - response payload shape unchanged for request/query paths
  - readiness precedence still deterministic
- Regression gate:
  - emergency_reinforcement_state.spec.luau
  - emergency_reinforcement_service_runtime_entrypoint.spec.luau
  - escape_service_runtime_entrypoint.spec.luau
  - headless_match_simulation.spec.luau
  - final_exit_state.spec.luau

## Out of Scope (Slice C)
- HUD/icon/countdown presentation
- multi-reinforcement variants
- persistence of reinforcement call state
