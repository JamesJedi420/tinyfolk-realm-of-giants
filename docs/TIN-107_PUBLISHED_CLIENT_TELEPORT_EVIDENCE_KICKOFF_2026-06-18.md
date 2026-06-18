# TIN-107 Published-Client Teleport Evidence — Kickoff

**Date:** 2026-06-18  
**Issue:** [TIN-107](https://linear.app/spectranoir/issue/TIN-107)  
**Milestone:** Admission and Queueing  
**Related:** [TIN-49](https://linear.app/spectranoir/issue/TIN-49) (architecture), [TIN-50](https://linear.app/spectranoir/issue/TIN-50) (location state), [TIN-51](https://linear.app/spectranoir/issue/TIN-51) (realm entry portal), [TIN-52](https://linear.app/spectranoir/issue/TIN-52) (safe return), [TIN-54](https://linear.app/spectranoir/issue/TIN-54) (realm load), [TIN-59](https://linear.app/spectranoir/issue/TIN-59) (raid board), [TIN-104](https://linear.app/spectranoir/issue/TIN-104) (reserved server allocation), [TIN-106](https://linear.app/spectranoir/issue/TIN-106) (handoff tokens), [TIN-117](https://linear.app/spectranoir/issue/TIN-117) (admission queue), [TIN-120](https://linear.app/spectranoir/issue/TIN-120) (party matchmaking), [TIN-58](https://linear.app/spectranoir/issue/TIN-58) (party system)

## Goal

Prove the live Roblox teleport boundary for the admission stack end-to-end on a **published** place. Wire bounded runtime evidence hooks so each approved transfer path emits schema-valid `[TeleportEvidence]` log lines at request, in-flight, and terminal phases, then execute the published-client checklist in `docs/PUBLISHED_CLIENT_TELEPORT_TEST_PLAN.md` and record pass/fail evidence for Linear closure.

This slice closes the validation gap explicitly deferred from TIN-104, TIN-59, TIN-50, TIN-52, and TIN-121.

## Prerequisites

| Dependency | Status | Notes |
|---|---|---|
| `PublishedClientTeleportEvidence` payload contract | **Done** | `Shared/GiantRealm/PublishedClientTeleportEvidence.luau` |
| Pure payload spec | **Done** | `tests/published_client_teleport_evidence.spec.luau` |
| Published-client runbook | **Done** | `docs/PUBLISHED_CLIENT_TELEPORT_TEST_PLAN.md` |
| Admission queue + dispatch | **Done** | `RealmAdmissionQueueService`, `RealmTeleportDispatcher` |
| Handoff orchestration | **Done** | `ProfileTeleportHandoffService` |
| Reserved-server routing | **Done** | TIN-104 `RealmReservedServerAllocationService` |
| Location state wiring | **Done** | TIN-50 `PlayerLocationService`, `RealmAdmissionLocationCaller` |
| Realm entry portal | **Done** | TIN-51 `RealmEntryPortalHubService` |
| Safe return | **Done** | TIN-52 `RealmSafeReturnService` |
| Raid board queue | **Done** | TIN-59 `RaidBoardHubService` |
| Party matchmaking admission | **Done** | TIN-120 `PartyMatchmakingAdmissionService` |
| Runtime evidence hook wiring | **Not started** | Hooks exist but are not called from teleport services |

## Slice boundary (in scope)

### Shared evidence helper (existing)

- Keep `PublishedClientTeleportEvidence` as the single payload authority (`schemaVersion=1`).
- Use `BuildPayload` validation before every log emission.
- Emit via `FormatLogLine` to server Output (and optional bounded `EventLogService` debug category when already wired for teleport diagnostics).

### Runtime hook wiring (new)

Add a thin server-only caller (e.g. `PublishedClientTeleportEvidenceCaller`) that:

- Resolves live environment fields: `placeId`, `jobId`, `privateServerId`, `timestamp`.
- Reads `locationState` from `_PlayerLocationService_QueryAPI.GetLocationSnapshot` when available.
- Maps terminal handoff/dispatch reasons to `resultReason` without leaking secrets.
- Invokes the correct flow hook:
  - `DebugRecordRealmEntryTeleportEvidence`
  - `DebugRecordEscapeReturnTeleportEvidence`
  - `DebugRecordFailedTransferTeleportEvidence`
  - `DebugRecordPartyTransferTeleportEvidence`

**Hook insertion points (minimum):**

| Service | Phases | Flow mapping |
|---|---|---|
| `ProfileTeleportHandoffService` | `BeginCrossServerHandoff` → requested; pre-teleport → teleporting; `OrchestrateDestinationArrival` confirm → arrived/returned; reject/rollback → failed | `realm_entry`, `escape_return`, `failed_transfer`, `party_transfer` (by `transitReason` / handoff context) |
| `RealmTeleportDispatcher` | pre-dispatch → requested; `TeleportToPrivateServer` invoke → teleporting; dispatch rejection → failed | `realm_entry` or `party_transfer`; failures → `failed_transfer` |
| `RealmAdmissionQueueProcessor` | non-retryable dispatch failure after location begin → failed | `failed_transfer` |
| `RealmSafeReturnService` | safe-return orchestration begin → requested; teleport handoff → teleporting; hub arrival → returned | `escape_return` |

Hooks must be **best-effort** (pcall + warn on fault) and must not change transfer authority or ordering.

### Approved published-client entry paths (evidence triggers)

At least one path per flow must be exercised on published clients:

| Flow | Approved trigger paths (pick one primary + one alternate where noted) |
|---|---|
| `realm_entry` | Raid board queue (TIN-59), realm entry portal (TIN-51), party matchmaking match (TIN-120) |
| `escape_return` | Route escape success, `RealmSafeReturnService` pending-return on join, portal hub return |
| `failed_transfer` | Queue to unallocated public realm (cold start before Giant load), invalid target realm id, admission enqueue rejection after transit begin |
| `party_transfer` | Party raid-board queue (TIN-58 + TIN-59) or party matchmaking admission (TIN-120) with ≥2 clients |

### Evidence documentation

- Add `docs/TIN-107_PUBLISHED_CLIENT_TELEPORT_EVIDENCE_2026-06-18.md` (or dated evidence doc) with pass/fail table per flow.
- Post Linear comment using the template in `docs/PUBLISHED_CLIENT_TELEPORT_TEST_PLAN.md`.

## Out of scope / deferred

- New matchmaking, registry, routing, or permission logic.
- Economy, capture, custody, or inventory behavior changes.
- Broad gameplay QA beyond the four teleport flows.
- External telemetry platform integration.
- TIN-50 `realmAssignment` consolidation (separate follow-up).
- TIN-14 hub district growth.
- Multi-universe / separate hub-place deployment (document blockers if production topology differs from single published place).

## Evidence payload contract

Required fields on every accepted log line:

| Field | Source |
|---|---|
| `schemaVersion` | `1` (helper constant) |
| `flow` | `realm_entry` \| `escape_return` \| `failed_transfer` \| `party_transfer` |
| `phase` | `requested` \| `reserved` \| `teleporting` \| `arrived` \| `returned` \| `failed` |
| `resultReason` | Deterministic service reason (e.g. `accepted`, `dispatch_rejected`, `handoff_token_mismatch`) |
| `timestamp` | `os.clock()` or `DateTime` seconds at emission |
| `placeId` | `game.PlaceId` |
| `jobId` | `game.JobId` |
| `privateServerId` | `game.PrivateServerId` (empty string allowed on public servers) |
| `realmId` | Target or source realm id from handoff/admission context |
| `userId` | Transfer subject |
| `locationState` | `PlayerLocationState` location string (e.g. `shared_hub`, `realm_guest`, `transit`, `return_pending`) |

Optional correlation fields when available: `sourcePlaceId`, `targetPlaceId`, `role`, `partyId`, `transferId`.

Log format: `[TeleportEvidence] ...` via `FormatLogLine`.

## Acceptance criteria — pre-test setup

Maps to **Before testing** in `docs/PUBLISHED_CLIENT_TELEPORT_TEST_PLAN.md`.

| # | Criterion | Pass condition |
|---|---|---|
| P1 | Published place | Target place version is published; not a local `.rbxlx` session |
| P2 | Traceability | Git commit, Roblox place version, universe ID, place ID, and TIN-107 linked in evidence doc |
| P3 | Hook surface | Runtime evidence hooks are wired and enabled for teleport services in the published build |
| P4 | Fresh session | Test starts from a new published client join with Output capture open |
| P5 | Local contract | `lune run tests/published_client_teleport_evidence.spec.luau` passes on the shipping commit |

## Acceptance criteria — `realm_entry` flow

Maps to **Realm entry** checklist steps 1–5.

| # | Criterion | Pass condition | Evidence |
|---|---|---|---|
| RE1 | Role + starting world | Player begins as Tinyfolk in shared hub (`locationState=shared_hub`) | Pre-transfer snapshot or attribute |
| RE2 | Approved entry path | Transfer triggered via raid board, realm portal, or party matchmaking admission | Manual step note |
| RE3 | Phase coverage | At least one `[TeleportEvidence]` line per phase: `requested`, `teleporting`, and `arrived` **or** terminal `failed` | Output log lines |
| RE4 | Flow tag | All lines use `flow=realm_entry` | Log parse |
| RE5 | Arrival state | On success, arrived client has role Tinyfolk (or classified entry role) and `locationState=realm_guest` (or valid invader/captured per entry method) | Post-arrival snapshot |
| RE6 | Environment fields | Terminal success payload includes non-empty `placeId`, `jobId`, `realmId`, `userId`; `privateServerId` present (may be empty on public routing) | Log parse |
| RE7 | Reserved routing | Public realm join uses durable reserved access code (TIN-104), not per-dispatch `ReserveServer` fallback | `privateServerId` / access-code correlation in log + dispatcher diagnostics |

**Primary implementation seam:** `ProfileTeleportHandoffService.BeginCrossServerHandoff` → `OrchestrateDestinationArrival`.

## Acceptance criteria — `escape_return` flow

Maps to **Escape return** checklist steps 1–5.

| # | Criterion | Pass condition | Evidence |
|---|---|---|---|
| ER1 | Starting context | Player begins in Giant realm as Tinyfolk with realm-scoped `locationState` | Pre-return snapshot |
| ER2 | Approved return path | Valid route escape, safe-return orchestration, or portal return path completes | Manual step note |
| ER3 | Phase coverage | Lines for `requested`, `teleporting`, and `returned` **or** terminal `failed` | Output log lines |
| ER4 | Flow tag | All lines use `flow=escape_return` | Log parse |
| ER5 | Hub arrival state | On success, `locationState=shared_hub` (not realm guest/transit) | Post-return snapshot |
| ER6 | Realm correlation | `realmId` matches the departed Giant realm across phases | Log parse |
| ER7 | No duplicate side effects | Return does not double-apply escape rewards, custody release, or inventory grants | Gameplay spot-check |

**Primary implementation seam:** `RealmSafeReturnService` + escape success path in `EscapeService` / `ProfileTeleportHandoffService.ConfirmDestinationOwnership` (`ConfirmHubReturn`).

## Acceptance criteria — `failed_transfer` flow

Maps to **Failed transfer** checklist steps 1–5.

| # | Criterion | Pass condition | Evidence |
|---|---|---|---|
| FT1 | Controlled failure | Failure triggered with invalid/unavailable target or non-retryable dispatch (not random disconnect) | Manual step note |
| FT2 | Terminal phase | At least one line with `phase=failed` | Output log |
| FT3 | Flow tag | Lines use `flow=failed_transfer` | Log parse |
| FT4 | Specific reason | `resultReason` is a deterministic service reason (not generic `error`); examples: `reserved_server_unallocated`, `target_realm_id_invalid`, `dispatch_rejected`, `handoff_token_mismatch` | Log parse |
| FT5 | Safe location | Player remains in or returns to a valid safe state (`shared_hub`, `return_pending`, or aborted `transit` → hub) | Location snapshot after failure |
| FT6 | No partial success | No duplicate rewards, escape resolution, custody mutation, or inventory change from the failed attempt | Gameplay spot-check |
| FT7 | Location rollback | When transit began before failure, `PlayerLocationService` shows abort/rollback (TIN-50 wiring) | Snapshot + admission diagnostics |

**Primary implementation seams:** `RealmTeleportDispatcher` rejection paths, `RealmAdmissionQueueProcessor` non-retryable failures, `ProfileTeleportHandoffService` begin/confirm rejections.

## Acceptance criteria — `party_transfer` flow

Maps to **Party transfer** checklist steps 1–5.

| # | Criterion | Pass condition | Evidence |
|---|---|---|---|
| PT1 | Party size | Test party has ≥2 clients | Session setup note |
| PT2 | Approved party path | Party raid-board queue or party matchmaking admission dispatches all members | Manual step note |
| PT3 | Per-member evidence | Each user emits `[TeleportEvidence]` for `requested`, `teleporting`, and `arrived`/`returned` or `failed` | Output logs per `userId` |
| PT4 | Flow tag | Lines use `flow=party_transfer` | Log parse |
| PT5 | Correlation | Shared `partyId` or `transferId` across members for the same operation | Log parse |
| PT6 | All-or-explicit-failure | All expected members arrive **or** each failure logged with specific `resultReason` (no silent partial success) | Per-member terminal phases |
| PT7 | Partial outcome clarity | If one member fails, remaining members' states are explicit in logs and location snapshots | Log + snapshot set |

**Primary implementation seams:** `PartyMatchmakingAdmissionService`, `RealmTeleportDispatcher` multi-member dispatch, `ProfileTeleportHandoffService` per-player handoff.

## Key files

| Area | Path |
|---|---|
| Evidence contract | `src/ReplicatedStorage/Shared/GiantRealm/PublishedClientTeleportEvidence.luau` |
| Evidence caller (new) | `src/ServerScriptService/Services/PublishedClientTeleportEvidenceCaller.luau` |
| Handoff orchestration | `src/ServerScriptService/Services/ProfileTeleportHandoffService.luau` |
| Dispatch | `src/ServerScriptService/Services/RealmTeleportDispatcher.luau` |
| Admission processor | `src/ServerScriptService/Services/RealmAdmissionQueueService.luau` |
| Safe return | `src/ServerScriptService/Services/RealmSafeReturnService.luau` |
| Location snapshots | `src/ServerScriptService/Services/PlayerLocationService.luau` |
| Raid board entry | `src/ServerScriptService/Services/RaidBoardHubService.server.luau` |
| Portal entry | `src/ServerScriptService/Services/RealmEntryPortalHubService.server.luau` |
| Party admission | `src/ServerScriptService/Services/PartyMatchmakingAdmissionService.server.luau` |
| Pure spec | `tests/published_client_teleport_evidence.spec.luau` |
| Runtime hook spec (new) | `tests/published_client_teleport_evidence_caller.spec.luau` or extend handoff/dispatcher entrypoint specs |
| Runbook | `docs/PUBLISHED_CLIENT_TELEPORT_TEST_PLAN.md` |

## Implementation plan

1. Add `PublishedClientTeleportEvidenceCaller` with environment + location snapshot assembly and best-effort log emission.
2. Wire caller into `ProfileTeleportHandoffService` at begin, confirm, orchestrate-arrival, and failure/rollback boundaries.
3. Wire caller into `RealmTeleportDispatcher` at dispatch request, teleport invoke, and rejection paths.
4. Wire caller into `RealmAdmissionQueueProcessor` for non-retryable dispatch failures after transit begin.
5. Wire caller into `RealmSafeReturnService` for escape-return orchestration phases.
6. Extend focused runtime specs to assert hook invocation (inject print sink or diagnostics counter) without requiring live `TeleportService`.
7. Run local validation suite; publish place; execute published checklist; write evidence doc + Linear comment.

## Validation

### Local (required before publish)

```powershell
.\scripts\run-validation.ps1 -ChangedOnly
lune run tests/published_client_teleport_evidence.spec.luau
lune run tests/profile_teleport_handoff_service_runtime_entrypoint.spec.luau
lune run tests/realm_teleport_dispatcher_runtime_entrypoint.spec.luau
lune run tests/realm_admission_queue_service_runtime_entrypoint.spec.luau
lune run tests/realm_safe_return_service_runtime_entrypoint.spec.luau
.\scripts\run-tests.ps1
rojo build default.project.json -o TinyfolkRealmOfGiants.rbxlx
```

### Published client (required for Done)

Follow `docs/PUBLISHED_CLIENT_TELEPORT_TEST_PLAN.md` for all four flows. Record results in `docs/TIN-107_PUBLISHED_CLIENT_TELEPORT_EVIDENCE_<date>.md`.

## Risks

| Risk | Mitigation |
|---|---|
| Published place unavailable | Ship hook wiring + local specs; mark issue **In Progress** with evidence blocker noted |
| `ReserveServer` / quota limits on live test | Use TIN-104 durable allocation path; retry with pre-warmed Giant realm owner session |
| Single-place prototype vs production hub/realm split | Document topology in evidence; do not block hook wiring on multi-place deployment |
| Hook fault breaks transfer | Best-effort pcall only; never gate handoff on evidence emission |
| Party test needs 2+ published clients | Schedule paired test session; log per-user evidence separately |
| Cold-start public realm | Expect `reserved_server_unallocated` for `failed_transfer` path until Giant owner loads once |

## Exit criteria (issue Done)

- [ ] Runtime hooks wired at all minimum insertion points
- [ ] Local validation + full Lune suite green
- [ ] Published-client evidence doc exists with PASS for RE*, ER*, FT*, PT* criteria (or explicit FAIL with follow-up issue links)
- [ ] Linear comment posted with representative `[TeleportEvidence]` lines
- [ ] Closure doc `docs/TIN-107_PUBLISHED_CLIENT_TELEPORT_EVIDENCE_CLOSURE_<date>.md` records shipped scope and deferred follow-ups
