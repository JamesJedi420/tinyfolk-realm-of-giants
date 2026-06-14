# TIN-75 Repeated Targeting / Abuse Detection Kickoff (2026-06-14)

## Issue

- ID: TIN-75
- Title: Repeated targeting / abuse detection
- Milestone: Capture, Rescue, and Routing
- Linear: https://linear.app/spectranoir/issue/TIN-75/repeated-targeting-abuse-detection

## Goal

Detect repeated targeting and custody-loop abuse patterns server-side, log suspicious loops, and integrate with existing score/reputation anti-farming seams without shipping moderation UI.

## Scope

- Add shared `RepeatedTargetingAbuseState` for pair/target/transfer loop detection and bounded suspicious-loop retention.
- Add `RepeatedTargetingAbuseConfig` tuning and readable debug attribute names.
- Add `RepeatedTargetingAbuseService` query API and runtime event-log hooks.
- Hook capture start, custody end, custody transfer settle, and pair reward cap events from existing capture/custody services.

## Boundary

- Server-authoritative detection + query API; readable attributes or debug snapshots only.
- No moderation UI (TIN-75/TIN-139 boundary).
- No ransom board (TIN-70) or structure catalog polish (TIN-61/TIN-87 deferred).

## Validation

```powershell
.\scripts\run-validation.ps1 -ChangedOnly
lune run tests/repeated_targeting_abuse_state.spec.luau
lune run tests/repeated_targeting_abuse_service_runtime_entrypoint.spec.luau
.\scripts\run-tests.ps1
```
