# TIN-75 Enforcement Slice Kickoff (2026-06-15)

## Issue

- ID: TIN-75
- Title: Repeated targeting / abuse detection
- Linear: https://linear.app/spectranoir/issue/TIN-75/repeated-targeting-abuse-detection

## Goal

Ship server-authoritative enforcement on top of the detection foundation: temporary custody interaction blocks and reward dampening beyond existing pair reward caps.

## Scope

- Extend `RepeatedTargetingAbuseConfig` with custody block duration, reward dampening window/multipliers, and enforcement attribute names.
- Extend `RepeatedTargetingAbuseState` with active custody blocks, `ResolveCustodyInteractionBlock`, and `ResolveRewardDampeningMultiplier`.
- Extend `RepeatedTargetingAbuseService` query API: `IsCustodyInteractionBlocked`, `GetRewardDampeningMultiplier`, attribute projection.
- Wire `CaptureService` and `CustodyTransferService` to reject blocked custody interactions (`repeated_targeting_custody_blocked`).
- Wire `ContainmentRewardResolver` to apply abuse dampening multiplier on top of pair reward multipliers.

## Boundary

- Enforcement only; moderation report hooks remain TIN-139.
- No moderation UI or player-facing appeal flows.
- Pair reward cap behavior (4th reward = zero) unchanged; dampening stacks on rewards 1–3 when recent suspicious loops match.

## Validation

```powershell
.\scripts\run-validation.ps1 -ChangedOnly
lune run tests/repeated_targeting_abuse_state.spec.luau
lune run tests/repeated_targeting_abuse_service_runtime_entrypoint.spec.luau
lune run tests/containment_reward_resolver.spec.luau
.\scripts\run-tests.ps1
```
