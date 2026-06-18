# TIN-107 Published-Client Teleport Evidence (2026-06-18)

**Issue:** [TIN-107](https://linear.app/spectranoir/issue/TIN-107)  
**Date:** 2026-06-18  
**Slice:** Manual published-place validation (remainder after PR #130 hook wiring)  
**Git commit:** `ea2ed64a32767b44b9646edd1c84ef3da93af91a` (master — TIN-107 hook wiring merged)

## Traceability (pre-publish)

| Field | Value |
|---|---|
| Git commit | `ea2ed64a32767b44b9646edd1c84ef3da93af91a` |
| Roblox place version | **PENDING** — publish from Studio after syncing master build |
| Universe ID | **PENDING** — record from Creator Dashboard after publish |
| Place ID | **PENDING** — record from Creator Dashboard after publish |
| Linked issue | TIN-107 |

## Session status

| Area | Status | Notes |
|---|---|---|
| Runtime hook wiring (PR #130) | **DONE** | `PublishedClientTeleportEvidenceCaller` + service insertion points on master |
| Local payload + caller specs | **PASS** | See validation block below |
| Runtime entrypoint specs | **PASS** | Handoff, dispatcher, safe-return entrypoints green; emit `[TeleportEvidence]` in Lune only |
| Fresh Rojo build | **DONE** | `rojo build default.project.json -o TinyfolkRealmOfGiants.rbxlx` (2026-06-18) |
| Studio opened | **DONE** | `.\scripts\open-studio-place.ps1 -Build` |
| Published-client four-flow checklist | **BLOCKED** | Requires linked-place publish + live client play; agent cannot complete autonomously without universe/place IDs and interactive Roblox sessions |

**Blocker:** Published-client teleport proof needs a **published** Roblox place (not local `.rbxlx` Play Solo), Output capture on the **server** job handling each transfer, and a **2-client** session for party transfer. No universe/place IDs or Open Cloud publish key are stored in-repo; Linear MCP was unauthorized in the agent session for status/comment updates.

## Local validation (pre-publish — P5)

```powershell
lune run tests/published_client_teleport_evidence.spec.luau
lune run tests/published_client_teleport_evidence_caller.spec.luau
lune run tests/profile_teleport_handoff_service_runtime_entrypoint.spec.luau
lune run tests/realm_teleport_dispatcher_runtime_entrypoint.spec.luau
lune run tests/realm_safe_return_service_runtime_entrypoint.spec.luau
```

All commands passed on 2026-06-18 against `ea2ed64a`.

Representative **headless** evidence lines (not published-client proof):

```text
[TeleportEvidence] schemaVersion=1 flow=realm_entry phase=requested resultReason=accepted placeId=1 jobId=job-unavailable ...
[TeleportEvidence] schemaVersion=1 flow=realm_entry phase=teleporting resultReason=accepted placeId=1 jobId=job-unavailable ...
[TeleportEvidence] schemaVersion=1 flow=realm_entry phase=arrived resultReason=accepted placeId=1 jobId=job-unavailable ...
[TeleportEvidence] schemaVersion=1 flow=escape_return phase=requested resultReason=accepted ...
[TeleportEvidence] schemaVersion=1 flow=escape_return phase=returned resultReason=accepted ...
[TeleportEvidence] schemaVersion=1 flow=failed_transfer phase=failed resultReason=target_realm_id_invalid ...
[TeleportEvidence] schemaVersion=1 flow=failed_transfer phase=failed resultReason=reserved_server_unallocated ...
```

## Publish procedure (operator — completes P1–P4)

1. In the opened Studio session (`TinyfolkRealmOfGiants.rbxlx`), link to the canonical experience if not already linked: **File → Publish to Roblox As…** → select the Tinyfolk experience (do not create a stray new universe for evidence).
2. Enable **Game Settings → Security → Enable Studio Access to API Services** (required for admission/MemoryStore paths).
3. **File → Publish to Roblox** (not Save to File). Record **place version**, **universe ID**, and **place ID** in the table above.
4. Join the **published** experience from the Roblox client (fresh session — not Studio Play Solo).
5. Open **View → Output**, filter for `[TeleportEvidence]`, and keep server Output visible for each flow.

Optional Rojo live-sync before publish: from repo root, `rojo serve` + Rojo Studio plugin **Connect** if the place is already linked.

## Operator runbook — four flows

Use these helpers on the **server** Output job after each step:

```lua
local function snap(userId)
	local api = _G._PlayerLocationService_QueryAPI
	return api and api.GetLocationSnapshot(userId)
end
local p = game.Players:GetPlayers()[1]
print("location", snap(p.UserId))
```

### Flow 1 — `realm_entry` (primary: raid board)

**Trigger path:** Tinyfolk in shared hub → **F** at `RaidBoardHub_A` → open raid board → queue into a **live public** Giant realm that already has a warmed owner allocation (TIN-104).

| Step | Action |
|---|---|
| 1 | Join published place as Tinyfolk; confirm `locationState=shared_hub` (RE1). |
| 2 | Move to raid board anchor; press **F** (`raid_board_open`). |
| 3 | Select a listed public realm with active registry entry; submit queue. |
| 4 | Capture `[TeleportEvidence]` with `flow=realm_entry` for `requested`, `teleporting`, and `arrived` (RE3–RE4). |
| 5 | After arrival, confirm `locationState=realm_guest` (or valid invader/captured per entry method) (RE5). |
| 6 | Verify terminal line includes real `placeId`, `jobId`, `realmId`, `userId`; `privateServerId` present (may be empty on public routing) (RE6). |
| 7 | Confirm dispatch used TIN-104 durable access code (not ephemeral `ReserveServer` fallback) via dispatcher diagnostics / allocation correlation (RE7). |

**Alternate paths (optional):** realm entry portal (F at portal hub), party matchmaking admission (TIN-120).

### Flow 2 — `escape_return`

**Prerequisite:** Complete Flow 1 (or otherwise arrive in a Giant realm as Tinyfolk).

**Trigger path:** Valid **route escape** to completion, or `RealmSafeReturnService` pending-return on rejoin, or portal hub return.

| Step | Action |
|---|---|
| 1 | Confirm pre-return `locationState` is realm-scoped (`realm_guest`, `realm_invader`, etc.) (ER1). |
| 2 | Complete an approved return (escape route success preferred for spot-check). |
| 3 | Capture `flow=escape_return` lines for `requested`, `teleporting`, and `returned` (ER3–ER4). |
| 4 | Confirm post-return `locationState=shared_hub` (ER5). |
| 5 | Verify `realmId` matches departed realm across phases (ER6). |
| 6 | Spot-check no duplicate escape rewards / custody / inventory grants (ER7). |

### Flow 3 — `failed_transfer` (controlled)

Pick **one** controlled failure (FT1):

| Method | Expected `resultReason` | Notes |
|---|---|---|
| **A — Cold public realm** | `reserved_server_unallocated` | Queue raid board target with **no** warmed Giant owner session / allocation yet (kickoff risk note). |
| **B — Invalid target realm id** | `target_realm_id_invalid` | Raid board queue with non-existent `realmId`, or server command bar handoff with invalid id (see below). |
| **C — Dispatch rejection** | `dispatch_rejected` or admission non-retryable reason | When dispatcher rejects after transit begin. |

Server command bar example for method B (after ownership ready):

```lua
local p = game.Players:GetPlayers()[1]
local api = _G._ProfileTeleportHandoffService_QueryAPI
local result = api and api.BeginCrossServerHandoff(p, {
	targetRealmId = "giant_realm_evidence_invalid",
	assignmentReason = "realm_entry_invader",
})
print(result)
```

| Step | Action |
|---|---|
| 1 | Trigger controlled failure (not random disconnect) (FT1). |
| 2 | Capture `flow=failed_transfer`, `phase=failed` with specific `resultReason` (FT2–FT4). |
| 3 | Confirm player in safe state: `shared_hub`, `return_pending`, or aborted `transit` → hub (FT5). |
| 4 | Spot-check no partial rewards / custody / inventory side effects (FT6). |
| 5 | If transit began, confirm location rollback via snapshot + admission diagnostics (FT7). |

### Flow 4 — `party_transfer` (≥2 clients)

**Session:** Published place, **two** Roblox clients (second account or Test → Start Server + 2 Players on published join is **not** valid — must be published clients per runbook).

| Step | Action |
|---|---|
| 1 | Form party of ≥2 Tinyfolk via in-game party UI / `TinyfolkPartyService` remotes (PT1). |
| 2 | Party leader triggers **party raid-board queue** or **party matchmaking admission** (PT2). |
| 3 | Capture per-`userId` `[TeleportEvidence]` for `requested`, `teleporting`, and `arrived` or terminal `failed` (PT3–PT4). |
| 4 | Verify shared `partyId` or `transferId` across members for the same operation (PT5). |
| 5 | Confirm all members arrive or each failure has explicit `resultReason` (PT6–PT7). |

**Warm-up note:** For successful party **arrival** (not failure path), pre-warm target Giant realm allocation same as Flow 1.

## Acceptance criteria mapping

### Pre-test setup

| # | Criterion | Result | Evidence |
|---|---|---|---|
| P1 | Published place | **BLOCKED** | Awaiting Studio publish + published client join |
| P2 | Traceability | **PARTIAL** | Git commit + issue linked; Roblox IDs pending |
| P3 | Hook surface | **PASS** | PR #130 on master; hooks in handoff/dispatch/admission/safe-return |
| P4 | Fresh published session | **BLOCKED** | Awaiting operator published join |
| P5 | Local contract spec | **PASS** | Lune specs green (see above) |

### `realm_entry` (RE*)

| # | Criterion | Result | Evidence |
|---|---|---|---|
| RE1 | Tinyfolk starts in `shared_hub` | **PENDING** | |
| RE2 | Approved entry path used | **PENDING** | Primary: raid board |
| RE3 | Phase coverage requested/teleporting/arrived | **PENDING** | |
| RE4 | `flow=realm_entry` | **PENDING** | |
| RE5 | Arrival role + `realm_guest` (or valid entry role) | **PENDING** | |
| RE6 | Environment fields on terminal success | **PENDING** | |
| RE7 | TIN-104 reserved routing | **PENDING** | |

### `escape_return` (ER*)

| # | Criterion | Result | Evidence |
|---|---|---|---|
| ER1 | Starts in Giant realm as Tinyfolk | **PENDING** | |
| ER2 | Approved return path | **PENDING** | |
| ER3 | Phase coverage requested/teleporting/returned | **PENDING** | |
| ER4 | `flow=escape_return` | **PENDING** | |
| ER5 | Hub arrival `shared_hub` | **PENDING** | |
| ER6 | `realmId` correlation | **PENDING** | |
| ER7 | No duplicate side effects | **PENDING** | |

### `failed_transfer` (FT*)

| # | Criterion | Result | Evidence |
|---|---|---|---|
| FT1 | Controlled failure | **PENDING** | |
| FT2 | `phase=failed` | **PENDING** | |
| FT3 | `flow=failed_transfer` | **PENDING** | |
| FT4 | Specific `resultReason` | **PENDING** | |
| FT5 | Safe location after failure | **PENDING** | |
| FT6 | No partial success side effects | **PENDING** | |
| FT7 | Location rollback when transit began | **PENDING** | |

### `party_transfer` (PT*)

| # | Criterion | Result | Evidence |
|---|---|---|---|
| PT1 | Party size ≥2 | **PENDING** | |
| PT2 | Approved party path | **PENDING** | |
| PT3 | Per-member evidence | **PENDING** | |
| PT4 | `flow=party_transfer` | **PENDING** | |
| PT5 | Shared `partyId` / `transferId` | **PENDING** | |
| PT6 | All arrive or explicit per-member failure | **PENDING** | |
| PT7 | Partial outcome clarity | **PENDING** | |

## Published evidence log (paste after run)

_Replace `PENDING` rows above when flows complete. Keep representative lines here._

```text
# realm_entry
# [TeleportEvidence] ...

# escape_return
# [TeleportEvidence] ...

# failed_transfer
# [TeleportEvidence] ...

# party_transfer
# [TeleportEvidence] ...
```

## Linear comment template (post when all flows PASS)

```text
Published-client teleport evidence

Date: 2026-06-18
Git commit: ea2ed64a32767b44b9646edd1c84ef3da93af91a
Roblox place version: <fill>
Universe ID: <fill>
Place ID: <fill>
Issue: TIN-107

Flows checked:
* realm_entry: PASS/FAIL — raid board queue, phases requested/teleporting/arrived
* escape_return: PASS/FAIL — route escape / safe return
* failed_transfer: PASS/FAIL — reserved_server_unallocated or target_realm_id_invalid
* party_transfer: PASS/FAIL — 2-client party raid-board queue

Representative evidence lines:
* [TeleportEvidence] ...

Result: <summary>
Blockers: <if any>
Follow-up issues: <if any>
```

## Follow-up / exit

- **Do not move TIN-107 to Done** until all RE*, ER*, FT*, PT* rows are **PASS** with published `[TeleportEvidence]` lines.
- Re-authenticate Linear in Cursor to post the closure comment and update issue status.
- If cold-start `failed_transfer` blocks realm entry warm-up, file a scoped follow-up only when allocation warm-up is a product defect (expected per kickoff risk table).
