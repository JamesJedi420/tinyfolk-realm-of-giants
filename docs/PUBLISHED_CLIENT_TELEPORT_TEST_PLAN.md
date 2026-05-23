# Published-Client Teleport Test Plan

This runbook is the TIN-107 evidence path for teleport behavior that cannot be proven in Studio or headless Luau tests.

## Boundary

Use this checklist only for published Roblox client/server behavior:

* realm entry from a shared server into a Giant realm
* escape return from a Giant realm back to the shared Tinyfolk world
* failed transfer recovery
* party transfer behavior where more than one player is moved together

Do not use this runbook as broad gameplay QA. Local source behavior still uses pure-Luau tests, Rojo build checks, and Studio validation as described in `docs/TESTING.md`.

## Why Published Client Is Required

Studio and headless tests can verify deterministic state machines, request validation, save/apply seams, and local debug payload construction. They cannot prove the live Roblox teleport boundary because these details depend on a published place and live server context:

* `game.PlaceId`
* `game.JobId`
* `game.PrivateServerId`
* reserved or public server routing behavior
* actual client arrival after a transfer
* multi-player party transfer timing
* failed teleport callback and reconnect behavior

## Evidence Payload

Every published-client teleport evidence log should use the shared payload contract in:

```text
src/ReplicatedStorage/Shared/GiantRealm/PublishedClientTeleportEvidence.luau
```

Required fields:

* `schemaVersion`
* `flow`
* `phase`
* `resultReason`
* `timestamp`
* `placeId`
* `jobId`
* `privateServerId`
* `realmId`
* `userId`
* `locationState`

Optional fields:

* `sourcePlaceId`
* `targetPlaceId`
* `role`
* `partyId`
* `transferId`

Use the helper's `BuildPayload` validation before logging, then print `FormatLogLine(payload)` to Output. A public server may produce an empty `privateServerId`; the field must still be present.

## Debug Hook Contract

Future runtime remotes or debug commands for teleport work should emit the same evidence payload at each important phase. The shared helper already exposes these hook functions so future services can call them without re-encoding flow names:

* `DebugRecordRealmEntryTeleportEvidence`
* `DebugRecordEscapeReturnTeleportEvidence`
* `DebugRecordFailedTransferTeleportEvidence`
* `DebugRecordPartyTransferTeleportEvidence`

Each hook pins its flow, accepts explicit phase/result/environment context, builds the evidence payload through `PublishedClientTeleportEvidence.BuildPayload`, and returns the formatted line for logging. Hooks may also forward the payload into the event log if that remains bounded to recent debug visibility.

## Checklist

Before testing:

1. Publish the place version being tested.
2. Record the Git commit, Roblox place version, universe ID, place ID, and linked issue.
3. Confirm any required debug hooks are enabled only for the intended test surface.
4. Start from a fresh published client session, not a local `.rbxlx`.
5. Open Output/log capture before triggering transfers.

Realm entry:

1. Start as a Tinyfolk in the shared world.
2. Trigger the approved realm-entry path.
3. Capture evidence for `flow=realm_entry` at request, teleporting, and arrived or failed phase.
4. Verify the arrived client has the expected role and `locationState`.
5. Verify the payload includes `PlaceId`, `JobId`, `PrivateServerId`, `realmId`, and `userId`.

Escape return:

1. Start in a Giant realm as a Tinyfolk.
2. Resolve a valid escape or safe-return path.
3. Capture evidence for `flow=escape_return` at request, teleporting, and returned or failed phase.
4. Verify the returned client is no longer in the Giant realm location state.
5. Verify the payload preserves the same `realmId` for correlation.

Failed transfer:

1. Trigger a controlled failure path with an invalid or unavailable target context.
2. Capture evidence for `flow=failed_transfer`.
3. Verify `phase=failed` and `resultReason` is specific.
4. Verify the player remains in or returns to a safe valid location state.
5. Verify no duplicate reward, escape, custody, or inventory side effect is produced by the failed attempt.

Party transfer:

1. Create a test party with at least two clients.
2. Trigger the approved party transfer path.
3. Capture one evidence payload per user and phase with the same `partyId` or `transferId`.
4. Verify all expected party members arrive or all failures are resolved explicitly.
5. Verify partial outcomes are logged with specific `resultReason` values.

## Evidence Comment Template

Post the manual result back to the linked Linear issue using this shape:

```text
Published-client teleport evidence

Date:
Git commit:
Roblox place version:
Universe ID:
Place ID:
Issue:

Flows checked:
* realm_entry:
* escape_return:
* failed_transfer:
* party_transfer:

Representative evidence lines:
* [TeleportEvidence] ...

Result:
Blockers:
Follow-up issues:
```

## Verification

For the local payload contract, run:

```powershell
lune run tests/published_client_teleport_evidence.spec.luau
```

For changed Luau files, run:

```powershell
.\scripts\run-validation.ps1 -ChangedOnly
```
