# TIN-67 Cross-Server Transfer Orchestration Closure (2026-06-11)

## Shipped

- Added destination arrival orchestration to `ProfileTeleportHandoffService` (`OrchestrateDestinationArrival`, `StartDestinationOrchestration`, diagnostics query seam).
- Wired bootstrap in `ProfileTeleportHandoffService.server.luau` to run orchestration on player join.
- Destination flow restores pending recovery from profile, confirms ownership when lifecycle is ready (with retry via ownership callback), records discovered realms, and commits Tinyfolk capacity arrival when the capacity seam is available.
- Added `tests/profile_teleport_destination_orchestration_runtime_entrypoint.spec.luau`.

## Validation

- `.\scripts\run-validation.ps1 -ChangedOnly` — pass
- `lune run tests/profile_teleport_destination_orchestration_runtime_entrypoint.spec.luau` — pass
- `lune run tests/profile_teleport_handoff_service_runtime_entrypoint.spec.luau` — pass
- `lune run tests/profile_teleport_handoff_admission_ingress_runtime_entrypoint.spec.luau` — pass
- `.\scripts\run-tests.ps1` — pass

## Remaining TIN-67 scope

- Runtime skill unlock producer (once catalog has progression skills).

## Studio follow-up

Complete a realm admission handoff with multiple party members, leave, rejoin, and confirm `partyHistory` round-trips per member. Verify destination spawn unblocks only after profile ownership confirms and pending recovery clears.
