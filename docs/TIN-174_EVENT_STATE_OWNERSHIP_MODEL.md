# TIN-174 Event State Ownership Model

## Scope
This document defines the bounded contract added in TIN-174 for event-state ownership, write-back routing, and reconnect restoration rules.

This slice does not redesign save pipelines, transfer orchestration, or profile lifecycle wiring.

## Ownership Partitions
- player_profile: durable player preference fields.
- realm_profile: durable realm-scoped fields persisted through the existing giant realm save-root path.
- session_runtime: non-durable runtime event state for active-session behavior.

## Namespace Ownership Contract
- rolePreference -> player_profile
- specialistPreference -> player_profile
- emergencyReinforcement -> realm_profile
- shrinePersistence -> realm_profile
- rescuePersistence -> realm_profile
- captureRuntime -> session_runtime
- escapeRuntime -> session_runtime
- defenseRuntime -> session_runtime
- returnRuntime -> session_runtime

## Deterministic Write-Back Matrix
- capture outcome: session_runtime only.
- escape outcome: session_runtime only.
- defense outcome: session_runtime plus realm_profile.
- return outcome: session_runtime plus realm_profile.

All four outcomes explicitly exclude player_profile writes in this slice.

## Reconnect Restoration Rules
- no active event session: clear session_runtime projection.
- active session id mismatch: clear session_runtime projection.
- resolved active session: clear session_runtime projection.
- active matching session with runtime projection: reapply session_runtime projection.
- active matching session without runtime projection: no-op for runtime projection.

## Runtime Boundary
- The contract lives in `Shared/GiantRealm/EventStateOwnershipModel.luau` as a pure deterministic policy module.
- Tests live in `tests/event_state_ownership_model.spec.luau`.
- Existing profile/realm persistence ownership remains unchanged.