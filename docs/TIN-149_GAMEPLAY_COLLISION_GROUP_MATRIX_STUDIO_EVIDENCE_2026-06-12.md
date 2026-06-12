# TIN-149 Gameplay Collision Group Matrix Studio Evidence (2026-06-12)

## Issue

- ID: TIN-149 (deferred follow-up)
- Title: Implement gameplay collision group matrix — Studio spot-check runbook
- Related: TIN-150 physics ownership policy (ownership attributes included in checks)
- Date: 2026-06-12

## Goal

Manually verify representative map surfaces and runtime character states against the gameplay collision matrix and physics ownership policy in Roblox Studio.

## Scope

- Manual Studio Play validation only (no gameplay code changes in this slice).
- Spot-check tunnels, containment/cage surfaces, grab/carry interactions, escape pads, safe zones, and control trigger volumes.
- Confirm `CollisionGroupService` matrix registration and part assignment.
- Confirm `PhysicsOwnershipService` tier attributes on the same representative surfaces (TIN-150).

## Boundary

- Does not replace Lune specs (`tests/gameplay_collision_group_matrix.spec.luau`, `tests/collision_group_service_runtime_entrypoint.spec.luau`).
- Does not validate full map authoring coverage (CollectionService tag pass remains deferred).
- Snare trap artifacts are folder-only today; trap ownership is validated via Query API when BaseParts exist.

## Preconditions

1. Build a fresh place from repo root:

```powershell
rojo build default.project.json -o TinyfolkRealmOfGiants.rbxlx
```

2. Open `TinyfolkRealmOfGiants.rbxlx` in Studio (not a stale published place).
3. Enable **Game Settings → Security → Enable Studio Access to API Services** if profile-dependent steps are run later.
4. Start **Play Solo** (or **Test → Start Server + 2 Players** for live grab carry).

## Service startup checks

Paste in the **server** Command Bar after play starts:

```lua
local collisionApi = _G._CollisionGroupService_QueryAPI
local ownershipApi = _G._PhysicsOwnershipService_QueryAPI
print("collision.matrixRegistered", collisionApi and collisionApi.IsMatrixRegistered())
local diag = collisionApi and collisionApi.GetRegistrationDiagnostics()
if diag then
	print("collision.registeredGroups", table.concat(diag.registeredGroups, ", "))
	print("collision.appliedPairs", diag.appliedPairs)
end
print("ownership.diagnostics", ownershipApi and ownershipApi.GetDiagnostics())
```

**PASS criteria (startup):**

| Check | Expected |
|-------|----------|
| `collision.matrixRegistered` | `true` |
| `collision.registeredGroups` | includes all ten `Gameplay_*` groups |
| `collision.appliedPairs` | `>= 55` |
| `ownership.diagnostics` | table with `worldPartsAssigned > 0` after map scan |

## Helper: inspect a map part

Paste once, then call `inspectPart(workspace.Map.EscapeRoutes.EscapeRoute_A)` (adjust path as needed):

```lua
local function inspectPart(part)
	if not part or not part:IsA("BasePart") then
		print("inspectPart: not a BasePart", part)
		return
	end
	local collisionApi = _G._CollisionGroupService_QueryAPI
	print(string.format(
		"%s | CollisionGroup=%s | OwnershipTier=%s | OwnershipAssembly=%s | CanCollide=%s | CanTouch=%s",
		part:GetFullName(),
		tostring(part.CollisionGroup),
		tostring(part:GetAttribute("GameplayPhysicsOwnershipTier")),
		tostring(part:GetAttribute("GameplayPhysicsOwnershipAssembly")),
		tostring(part.CanCollide),
		tostring(part.CanTouch)
	))
	if collisionApi then
		local giantGroup = "Gameplay_Giant"
		local partGroup = part.CollisionGroup
		print("relation vs Giant", collisionApi.GetRelation(giantGroup, partGroup))
	end
end
```

## Scenario A — Tinyfolk tunnel / route geometry

**Map anchors**

- `Workspace.Map.EscapeRoutes.EscapeRoute_A` (`TinyfolkOnlyRoute=true`)
- Any `Workspace.Map.TinyfolkRoutes` segment with route markers near spawn

**Steps**

1. Run `inspectPart` on `EscapeRoute_A`.
2. In Explorer, confirm `CollisionGroup == Gameplay_TinyfolkRoute`.
3. Confirm relation vs Giant is `ignore`:

```lua
print(_G._CollisionGroupService_QueryAPI.GetRelation("Gameplay_Giant", "Gameplay_TinyfolkRoute"))
```

**PASS criteria**

| Check | Expected |
|-------|----------|
| `EscapeRoute_A.CollisionGroup` | `Gameplay_TinyfolkRoute` |
| Relation Giant × TinyfolkRoute | `ignore` |
| Ownership tier (anchored route) | `Automatic` (world geometry tier) |

## Scenario B — Containment / cage district

**Map anchors**

- `Workspace.Map.DistrictPads.DistrictPad_Containment` (`DistrictId=Containment`)
- Containment dressing near `(55, 0, -78)` if authored with `DistrictId=Containment`

**Steps**

1. Run `inspectPart` on `DistrictPad_Containment`.
2. Confirm `CollisionGroup == Gameplay_Containment`.
3. Confirm relation ContainedTinyfolk × Containment is `ignore`:

```lua
print(_G._CollisionGroupService_QueryAPI.GetRelation("Gameplay_ContainedTinyfolk", "Gameplay_Containment"))
```

**PASS criteria**

| Check | Expected |
|-------|----------|
| Containment pad `CollisionGroup` | `Gameplay_Containment` |
| Relation ContainedTinyfolk × Containment | `ignore` |
| Ownership assembly | `ContainmentStructure` when `DistrictId=Containment` |
| Ownership tier | `Server` |

## Scenario C — Grab zone / carry collision transition

Grab is range-based (no dedicated grab volume). Validate character collision groups and ownership during carry.

### Option 1 — Query API (single player)

Set up Giant + Tinyfolk roles via Command Bar, then request grab:

```lua
local Players = game:GetService("Players")
local giant = Players:GetPlayers()[1]
giant:SetAttribute("Role", "Giant")
-- For two-player server tests, pick a second player as tinyfolk:
local tinyfolk = Players:GetPlayers()[2] or giant
if tinyfolk == giant then
	warn("Use Start Server + 2 Players for live grab, or inject a second mock player in harness")
end
tinyfolk:SetAttribute("Role", "Tinyfolk")
local grab = _G._GrabService_QueryAPI.RequestGrab(giant.UserId, tinyfolk.UserId, os.clock())
print("grab", grab.accepted, grab.reason)
```

After accepted grab, inspect both characters:

```lua
local function inspectCharacter(player)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root then return end
	print(player.Name,
		"playerGroup", player:GetAttribute("GameplayCollisionGroup"),
		"playerAssembly", player:GetAttribute("GameplayPhysicsOwnershipCharacterAssembly"),
		"playerTier", player:GetAttribute("GameplayPhysicsOwnershipTier"),
		"rootCollisionGroup", root.CollisionGroup,
		"rootOwnershipTier", root:GetAttribute("GameplayPhysicsOwnershipTier"),
		"networkOwner", tostring(root:GetNetworkOwner()))
end
for _, p in Players:GetPlayers() do inspectCharacter(p) end
```

### Option 2 — Live two-player Studio session

1. **Test → Start Server + 2 Players**.
2. Player 1 selects Giant, Player 2 selects Tinyfolk (role picker UI or `Role` attribute).
3. Giant walks within grab range and grabs Tinyfolk (interaction key `F` or grab client).
4. Run `inspectCharacter` for both players.

**PASS criteria (carry active)**

| Actor | Collision group | Ownership assembly | Ownership tier | Network owner |
|-------|-----------------|-------------------|----------------|---------------|
| Carried Tinyfolk | `Gameplay_CarriedTinyfolk` | `CarriedTinyfolk` | `Server` | server (`nil`) |
| Carrying Giant | `Gameplay_Giant` (unchanged) | `CarryingGiant` | `Server` | server (`nil`) |

**Matrix check during carry**

```lua
print(_G._CollisionGroupService_QueryAPI.GetRelation("Gameplay_Giant", "Gameplay_CarriedTinyfolk"))
```

Expected: `ignore` (Giant does not physically collide with carried Tinyfolk).

## Scenario D — Escape pad / escape route

**Map anchors**

- `Workspace.Map.DistrictPads` pad with `DistrictId=EscapeWinPad` (near `(-150, 0, 16)`)
- `Workspace.Map.RouteNodes.Node_EscapeWinPad`
- `Workspace.Map.EscapeRoutes.EscapeRoute_A` (fallback escape candidate)

**Steps**

1. `inspectPart` on `EscapeRoute_A` — confirm `Gameplay_TinyfolkRoute`.
2. Walk Tinyfolk to escape route trigger radius (10 studs default) or query escape readiness:

```lua
local player = game.Players:GetPlayers()[1]
player:SetAttribute("Role", "Tinyfolk")
local escapeApi = _G._EscapeService_QueryAPI
if escapeApi and escapeApi.GetEscapeDebugSnapshot then
	print(escapeApi.GetEscapeDebugSnapshot(player.UserId))
end
```

3. Confirm Giant × TinyfolkRoute relation is `ignore` (Giants should not block Tinyfolk-only tunnel collision policy):

```lua
print(_G._CollisionGroupService_QueryAPI.GetRelation("Gameplay_Giant", "Gameplay_TinyfolkRoute"))
```

**PASS criteria**

| Check | Expected |
|-------|----------|
| Escape route collision group | `Gameplay_TinyfolkRoute` |
| Giant × TinyfolkRoute | `ignore` |
| Tinyfolk × TinyfolkRoute | `collide` (default unlisted pair) |

## Scenario E — Safe zone grab rejection

Safe zones are player/route attributes at runtime (`InSafeZone`, `SafeZoneType`).

**Steps**

1. Start Play Solo as Tinyfolk (default role).
2. Apply SharedHub safe-zone protection on the target player:

```lua
local EscapeConfig = require(game.ReplicatedStorage.Shared.Config.EscapeConfig)
local tinyfolk = game.Players:GetPlayers()[1]
tinyfolk:SetAttribute("Role", "Tinyfolk")
tinyfolk:SetAttribute(EscapeConfig.SafeZoneAttribute, true)
tinyfolk:SetAttribute(EscapeConfig.SafeZoneTypeAttribute, EscapeConfig.SafeZoneTypes.SharedHub)
```

3. **Requires two players.** Start Server + 2 Players. Player 1 = Giant, Player 2 = Tinyfolk (with safe-zone attributes from step 2 on the Tinyfolk player).

```lua
local players = game.Players:GetPlayers()
local giant = players[1]
local tinyfolk = players[2]
giant:SetAttribute("Role", "Giant")
tinyfolk:SetAttribute("Role", "Tinyfolk")
tinyfolk:SetAttribute(EscapeConfig.SafeZoneAttribute, true)
tinyfolk:SetAttribute(EscapeConfig.SafeZoneTypeAttribute, EscapeConfig.SafeZoneTypes.SharedHub)
local result = _G._GrabService_QueryAPI.RequestGrab(giant.UserId, tinyfolk.UserId, os.clock())
print("safeZoneGrab", result.accepted, result.reason)
```

**PASS criteria**

| Check | Expected |
|-------|----------|
| `result.accepted` | `false` |
| `result.reason` | safe-zone reason (e.g. `shared_hub_no_capture` or `target_in_safe_zone`) |
| Tinyfolk collision group while protected | remains `Gameplay_Tinyfolk` (no carry transition) |

## Scenario F — Control / trigger zone (touch, not collide)

**Map anchor:** `Workspace.Map.ControlZones.GiantControlZone_A`

**Steps**

1. `inspectPart` on `GiantControlZone_A`.
2. Confirm trigger heuristic assignment.

**PASS criteria**

| Check | Expected |
|-------|----------|
| `CollisionGroup` | `Gameplay_TriggerZone` |
| `CanCollide` | `false` |
| `CanTouch` | `true` |
| Relation Giant × TriggerZone | `touch` |
| Relation TriggerZone × WorldGeometry | `touch` |
| Ownership assembly | `TriggerZone` |
| Ownership tier | `Server` |

## Scenario G — Physics ownership debug client (Studio only)

With Play Solo running, open **View → Output**. The `PhysicsOwnershipDebugClient` logs snapshots on spawn:

```
[PhysicsOwnershipDebugClient] Player snapshot: userId=... assembly=... tier=... requiresServer=...
```

Manual refresh:

```lua
game.ReplicatedStorage.Remotes.PhysicsOwnershipDebugStateRequest:FireServer(nil)
```

**PASS criteria**

- Output contains at least one player snapshot per play session.
- Carried/contained players show `requiresServer=true` when applicable.

## Matrix relation quick reference

Run in server Command Bar to dump critical relations:

```lua
local api = _G._CollisionGroupService_QueryAPI
local pairs = {
	{"Gameplay_Giant", "Gameplay_Tinyfolk", "collide"},
	{"Gameplay_Giant", "Gameplay_CarriedTinyfolk", "ignore"},
	{"Gameplay_Giant", "Gameplay_TinyfolkRoute", "ignore"},
	{"Gameplay_Tinyfolk", "Gameplay_GiantRoute", "ignore"},
	{"Gameplay_ContainedTinyfolk", "Gameplay_WorldGeometry", "ignore"},
	{"Gameplay_TriggerZone", "Gameplay_WorldGeometry", "touch"},
}
for _, entry in ipairs(pairs) do
	local actual = api.GetRelation(entry[1], entry[2])
	local ok = actual == entry[3]
	print(ok and "PASS" or "FAIL", entry[1], entry[2], "expected", entry[3], "actual", actual)
end
```

## Evidence template

Record results in this table when executing the runbook:

| Scenario | Result (PASS/FAIL) | Notes | Date | Executor |
|----------|-------------------|-------|------|----------|
| Startup checks | | | | |
| A Tinyfolk tunnel | | | | |
| B Containment/cage | | | | |
| C Grab/carry | | | | |
| D Escape pad | | | | |
| E Safe zone | | | | |
| F Trigger zone | | | | |
| G Ownership debug client | | | | |
| Matrix relation dump | | | | |

## Automated proxy validation

These Lune specs cover deterministic policy logic without Studio:

```powershell
lune run tests/gameplay_collision_group_matrix.spec.luau
lune run tests/collision_group_service_runtime_entrypoint.spec.luau
lune run tests/gameplay_physics_ownership_policy.spec.luau
lune run tests/physics_ownership_service_runtime_entrypoint.spec.luau
```

## Known gaps (out of runbook scope)

- Build preview parts at runtime are not yet materialized; `Gameplay_BuildPreview` assignment deferred until preview parts exist.
- Snare trap artifacts under `Workspace.Map.GiantStructures` are folders without BaseParts; trap collision/ownership for physical trap meshes deferred.
- CollectionService tag authoring pass for map folders beyond attribute heuristics remains deferred.
