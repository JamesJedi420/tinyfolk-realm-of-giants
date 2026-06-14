# TIN-161 Defensive Prop Studio Spot-Check Evidence (2026-06-14)

## Issue

- ID: TIN-161
- Title: Implement defensive prop obstacle system
- Checklist: `docs/TIN-161_STUDIO_SPOTCHECK_CHECKLIST.md`
- Date: 2026-06-14

## Goal

Record PASS/FAIL for defensive prop drop, break, barrier, rescue-acceleration, and prop-family behavior after map sync. Close TIN-161 when acceptance criteria and checklist rows are satisfied.

## Automated validation (agent-run, 2026-06-14)

```powershell
.\scripts\run-validation.ps1 -ChangedOnly
lune run tests/defensive_prop_state.spec.luau
lune run tests/defensive_prop_service_runtime_entrypoint.spec.luau
.\scripts\run-tests.ps1
rojo build default.project.json -o TinyfolkRealmOfGiants.rbxlx
```

| Command | Result |
|---------|--------|
| `run-validation.ps1 -ChangedOnly` | PASS (no changed .luau under src/tests) |
| `defensive_prop_state.spec.luau` | PASS (39 checks) |
| `defensive_prop_service_runtime_entrypoint.spec.luau` | PASS (38 checks) |
| `run-tests.ps1` | PASS (full suite exit 0) |
| `rojo build` | PASS (`TinyfolkRealmOfGiants.rbxlx` built) |

## Source inspection (agent-run, 2026-06-14)

| Check | Expected | Result |
|-------|----------|--------|
| `DefensivePropService.server.luau` exposes drop/break/barrier/route query API | `_DefensivePropService_QueryAPI` with `RequestDrop`, `RequestStartBreak`, `RequestCompleteBreak`, `ResolveGiantBarrierContact`, `IsGiantMacroRouteBlocked` | **PASS** |
| Map props `DefensiveProp_A/B/C` authored | crate / shelf / rope_gate with zone pairing | **PASS** (`src/Workspace/Map/DefensiveProps/Layout.model.json`) |
| Map zones `DefensivePropZone_A/B/C` authored | radius 26, `TinyfolkDefense` tag | **PASS** (`src/Workspace/Map/DefensivePropZones/Layout.model.json`) |
| Giant macro routes at choke points | `GiantRoute_PlazaToHearth`, `GiantRoute_PlazaToWorkYard`, `GiantRoute_PlazaToStoneDistrict` | **PASS** (`src/Workspace/Map/GiantRoutes/Layout.model.json`) |
| Rescue acceleration on qualifying drop | `GrantRescueAcceleration` via `_RescueContractService_QueryAPI` | **PASS** (service + runtime spec) |
| Prop-type timing overrides | shelf 6s active; rope_gate 1s stagger | **PASS** (`DefensivePropConfig.PropTypes` + state spec) |

### Studio UX gap (not blocking automated acceptance)

- No `DefensivePropRequest` remote is created by `DefensivePropService` (binds only if pre-existing).
- No client `InteractionResolver` candidate or dedicated client script fires drop/break requests.
- Checklist row "Drop interaction available" (F-key proximity) requires **Query API command-bar testing** until a client interaction slice ships.

## Preconditions (Studio manual)

1. Build/sync: `rojo build default.project.json -o TinyfolkRealmOfGiants.rbxlx` and open in Studio.
2. Play with **Test → Start Server + 2 Players** (Tinyfolk + Giant).
3. Confirm anchors under `Workspace.Map.DefensiveProps.Layout` and `Workspace.Map.DefensivePropZones.Layout`.

## Service startup checks

Paste in the **server** Command Bar after play starts:

```lua
local api = _G._DefensivePropService_QueryAPI
print("defensiveProp.api", api ~= nil)
if api then
	local snap = api.GetPropSnapshot("DefensiveProp_A")
	print("DefensiveProp_A.state", snap and snap.state)
end
```

**PASS criteria:** `defensiveProp.api` is `true`; `DefensiveProp_A.state` is `Ready`.

## Helper: inspect prop + player attributes

```lua
local function inspectProp(propId)
	local part = workspace.Map.DefensiveProps.Layout:FindFirstChild(propId, true)
	if not part then
		print("missing", propId)
		return
	end
	print(propId,
		"state", part:GetAttribute("DefensivePropState"),
		"startupEnds", part:GetAttribute("DefensivePropBarrierStartupEndsAt"),
		"activeEnds", part:GetAttribute("DefensivePropBarrierActiveEndsAt"))
end

local function inspectGiantStagger(player)
	print(player.Name,
		"GiantBarrierStaggerActive", player:GetAttribute("GiantBarrierStaggerActive"),
		"GiantBarrierStaggerUntil", player:GetAttribute("GiantBarrierStaggerUntil"))
end

local function inspectRescueAccel(player)
	print(player.Name, "RescueAccelerationActive", player:GetAttribute("RescueAccelerationActive"))
end
```

## Drop flow (Tinyfolk) — checklist rows

Use Query API from server Command Bar (substitutes for F-key until client slice):

```lua
local Players = game:GetService("Players")
local api = _G._DefensivePropService_QueryAPI
local tinyfolk = nil
local giant = nil
for _, p in Players:GetPlayers() do
	if p:GetAttribute("Role") == "Tinyfolk" then tinyfolk = p end
	if p:GetAttribute("Role") == "Giant" then giant = p end
end
-- Position tinyfolk at DefensiveProp_A (0, 2.2, -28) before drop
local drop = api.RequestDrop(tinyfolk, "DefensiveProp_A")
print("drop", drop.accepted, drop.reason, drop.snapshot and drop.snapshot.state)
task.wait(1.1)
local snap = api.GetPropSnapshot("DefensiveProp_A")
print("after startup", snap.state)
print("route blocked", api.IsGiantMacroRouteBlocked("GiantRoute_PlazaToHearth"))
```

| Step | Action | Expected | Automated proxy | Studio manual |
|------|--------|----------|-----------------|---------------|
| 1 | Tinyfolk within 12 studs of `DefensiveProp_A` | Drop interaction available | Range validated in runtime spec | **PENDING** (no F-key client; use Query API) |
| 2 | Request drop | State → Dropped; route still traversable | **PASS** (runtime spec) | **PENDING** |
| 3 | Wait ~1s | State → Blocked; route blocked | **PASS** (state + runtime spec) | **PENDING** |
| 4 | Rescue-context drop | `RescueAccelerationActive` on dropper | **PASS** (runtime spec + `GrantRescueAcceleration` seam) | **PENDING** |

Rescue-context drop helper:

```lua
-- With active rescue contract on tinyfolk (set up via RescueContractService Query API or live rescue flow):
local drop = api.RequestDrop(tinyfolk, "DefensiveProp_A")
inspectRescueAccel(tinyfolk)
print("rescueDropEffect", drop.rescueDropEffect)
```

## Break flow (Giant) — checklist rows

```lua
local start = api.RequestStartBreak(giant, "DefensiveProp_A")
print("startBreak", start.accepted, start.snapshot and start.snapshot.breakInProgress)
task.wait(2.1)
local complete = api.RequestCompleteBreak(giant, "DefensiveProp_A")
print("completeBreak", complete.accepted, complete.snapshot and complete.snapshot.state)
```

Barrier contact during break (move Giant HRP onto prop during blocked window):

```lua
local contact = api.ResolveGiantBarrierContact(giant.UserId, workspace.Map.DefensiveProps.Layout.DefensiveProp_A.Position)
inspectGiantStagger(giant)
print("contact", contact.accepted, contact.breakInterrupted, contact.staggerSeconds)
```

| Step | Action | Expected | Automated proxy | Studio manual |
|------|--------|----------|-----------------|---------------|
| 1 | Giant within 14 studs | Break start available | **PASS** (runtime spec range) | **PENDING** |
| 2 | Start break | ~2s break-in-progress window | **PASS** (runtime spec) | **PENDING** |
| 3 | Complete break | Broken → Resetting → Ready | **PASS** (state + runtime spec) | **PENDING** |
| 4 | Contact during Blocked while breaking | Break cancels; stagger attrs | **PASS** (runtime spec) | **PENDING** |

## Prop families — checklist rows

| Prop | Type | Zone | Route | Timing (config) | Automated proxy | Studio manual |
|------|------|------|-------|-----------------|-----------------|---------------|
| `DefensiveProp_A` | crate | `DefensivePropZone_A` | `GiantRoute_PlazaToHearth` | 1s startup / 5s active | **PASS** | **PENDING** |
| `DefensiveProp_B` | shelf | `DefensivePropZone_B` | `GiantRoute_PlazaToWorkYard` | 6s active window | **PASS** (state spec) | **PENDING** |
| `DefensiveProp_C` | rope_gate | `DefensivePropZone_C` | `GiantRoute_PlazaToStoneDistrict` | 1s stagger | **PASS** (state spec) | **PENDING** |

## Acceptance criteria vs evidence

| Criterion | Status | Evidence |
|-----------|--------|----------|
| Props triggered into dropped obstacle state | **PASS** | `DefensivePropState.CreateDrop` + runtime spec |
| Shared lifecycle states | **PASS** | `defensive_prop_state.spec.luau` |
| Giant timed break clears prop | **PASS** | `StartBreak` / `CompleteBreak` + runtime spec |
| Startup + active barrier timing (not instant stun) | **PASS** | Dropped → Blocked transition + contact-only stagger |
| Asymmetric route pressure + Giant counterplay | **PASS** | `GiantBuildModeService` integration + barrier contact |
| Server-validated, Studio-testable | **PASS** (Query API) | Command-bar runbook above; F-key client deferred |

## Summary

- **Automated + source inspection:** all TIN-161 acceptance criteria **PASS**.
- **Studio Play checklist rows:** **PENDING** manual run (agent cannot execute Roblox Studio Play). Runbook and Query API helpers above mirror every checklist step.
- **Deferred (separate issues):** portable props; HUD/VFX/audio polish; F-key client interaction wiring for `DefensivePropRequest`.

## Recommended closeout

After a live Studio session fills the **PENDING** column with PASS:

1. Update the Studio manual column in this doc.
2. Add a Linear comment linking this evidence file.
3. Confirm TIN-161 remains **Done** (issue already merged via PRs #81, #82, #84).
