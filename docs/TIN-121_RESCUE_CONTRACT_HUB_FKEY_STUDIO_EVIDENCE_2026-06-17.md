# TIN-121 Rescue Contract Hub F-key Studio Evidence (2026-06-17)

**Linear status sync:** Issue is `Done`; comment posted (`63ea0ec0-0ba0-478b-bece-822f1b9e09be`).

## Issue

- ID: TIN-121
- Title: Implement rescue contract queue
- Slice: Hub board F-key smoke and queue acceptance spot-check
- Date: 2026-06-17

## Goal

Verify in Studio that Tinyfolk can open the rescue contract board via F-key at hub anchors, observe pending contracts, accept safely, and see refresh/expiry behavior remain consistent with server-authoritative queue rules.

## Scope

- Manual Studio validation runbook for board open/list/accept/refresh/expiry smoke checks.
- Evidence-oriented checks only (no gameplay code changes).
- Uses server Query API commands where needed to seed deterministic queue conditions for manual verification.

## Preconditions

- Roblox Studio with API services enabled.
- Fresh build from repo root:

```powershell
rojo build default.project.json -o TinyfolkRealmOfGiants.rbxlx
```

- Open `TinyfolkRealmOfGiants.rbxlx` in Studio.

## Playtest steps

### 1. Start Play Solo and move to board anchor

- Start Play Solo as Tinyfolk.
- Move near `RescueContractBoardHub_A`.
- Press **F** to trigger `rescue_contract_board_open`.

**Expected:** rescue board panel opens and status reads loading/no contracts.

### 2. Seed a rescue queue entry (server Command Bar)

Use server Command Bar to create a deterministic pending contract:

```lua
local players = game:GetService("Players"):GetPlayers()
local rescuer = players[1]
local target = players[2] or players[1]
target:SetAttribute("DownedIsDowned", true)
target:SetAttribute("GiantRealmOwnerUserId", 9001)
local api = _G._RescueContractService_QueryAPI
print("request", api and api.RequestRescueContract and api.RequestRescueContract(rescuer.UserId, target.UserId, os.clock()))
```

**Expected:** request returns `accepted = true` and a queue entry becomes available.

### 3. Refresh and list contracts

- Press Refresh on the panel (or close/reopen with F).

**Expected:** one or more rows render with realm/reward/danger/seconds-remaining copy.

### 4. Accept a contract from the board

- Click **Accept** on a row.
- Observe status message and subsequent list refresh.

**Expected:** accept response reports success (`accepted` or duplicate-safe accepted), row disappears from pending list, and no client error paths trigger.

### 5. Notify-driven refresh smoke

Trigger a hub notify from server Command Bar:

```lua
local hubApi = _G._RescueContractHubService_QueryAPI
if hubApi and hubApi.BroadcastNotify then
	hubApi.BroadcastNotify({ reason = "studio_smoke" })
end
```

**Expected:** if panel is open, list refreshes via coalesced notify behavior.

### 6. Expiry safety smoke

- Seed a short-lived contract entry (or wait for natural expiry).
- Attempt accept after expiry window.

**Expected:** expired entry is not returned as pending; stale accept attempts resolve safely (non-pending rejection path), with no duplicate side effects.

## Automated regression companion

```powershell
.\scripts\run-validation.ps1 -ChangedOnly
lune run tests/rescue_contract_hub_service_runtime_entrypoint.spec.luau
lune run tests/rescue_contract_service_runtime_entrypoint.spec.luau
```

2026-06-17 rerun: all checks passed.

## Studio runtime evidence table

| Step | Result | Notes |
|---|---|---|
| F-key opens board at `RescueContractBoardHub_A` | PENDING | Run in Play Solo and record pass/fail |
| Pending contracts list from seeded queue entry | PENDING | Validate row render + metadata |
| Accept removes row and returns success status | PENDING | Validate no duplicate or stale side effects |
| Notify refresh updates open panel | PENDING | Use `BroadcastNotify` smoke trigger |
| Expired contract safely rejects/clears | PENDING | Validate non-pending handling |
| Overall Studio smoke | PENDING | Mark PASS when all rows pass |

## Risk-focused checklist

- Confirm accept path stays safe when queue entry transitions from pending to non-pending mid-flow.
- Confirm panel behavior remains resilient when queue entry expires between list and accept.
- Confirm refresh behavior is reconcile/fanout based and does not imply durable party state.

## Related docs

- `docs/TIN-121_RESCUE_CONTRACT_QUEUE_KICKOFF_2026-06-17.md`
- `docs/TIN-121_RESCUE_CONTRACT_QUEUE_CLOSURE_2026-06-17.md`
- `docs/TIN-125_MESSAGING_SERVICE_RECONCILIATION_CLOSURE_2026-06-17.md`
- Linear issue comment posted: `63ea0ec0-0ba0-478b-bece-822f1b9e09be`
