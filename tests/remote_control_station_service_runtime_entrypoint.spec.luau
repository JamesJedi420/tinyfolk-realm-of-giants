--!nocheck
--!nolint BuiltinGlobalWrite
-- selene: allow(global_usage)

local MockPlayer = require("../tests/mocks/MockPlayer")

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(string.format("FAIL [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual)))
	end
	print(string.format("PASS [%s]", label))
end

local function assertTrue(condition: boolean, label: string)
	assertEqual(condition, true, label)
end

local function assertFalse(condition: boolean, label: string)
	assertEqual(condition, false, label)
end

local function makeNode(name: string, className: string?)
	local node: any = {
		Name = name,
		ClassName = className or "Folder",
		_Children = {},
	}
	function node:IsA(expectedClass: string): boolean
		return self.ClassName == expectedClass
	end
	function node:FindFirstChild(childName: string): any
		return self._Children[childName]
	end
	function node:WaitForChild(childName: string): any
		return self._Children[childName]
	end
	function node:GetDescendants(): { any }
		local descendants = {}
		for _, child in pairs(self._Children) do
			table.insert(descendants, child)
			if type(child.GetDescendants) == "function" then
				for _, descendant in ipairs(child:GetDescendants()) do
					table.insert(descendants, descendant)
				end
			end
		end
		return descendants
	end
	return node
end

local function addChild(parent: any, childName: string, child: any)
	parent._Children[childName] = child
	if type(child) == "table" then
		child.Parent = parent
	end
end

local function makePart(name: string, position: any, size: any?, attributes: any?): any
	local part = makeNode(name, "BasePart")
	part.Position = position
	part.Size = size or { x = 4, y = 4, z = 4 }
	part._Attributes = attributes or {}
	function part:GetAttribute(attributeName: string): any
		return self._Attributes[attributeName]
	end
	function part:SetAttribute(attributeName: string, value: any)
		self._Attributes[attributeName] = value
	end
	return part
end

local configFolder = makeNode("Config")
addChild(configFolder, "RemoteControlStationConfig", "../../ReplicatedStorage/Shared/Config/RemoteControlStationConfig")
addChild(configFolder, "EscapeConfig", "../../ReplicatedStorage/Shared/Config/EscapeConfig")
addChild(configFolder, "RoleConfig", "../../ReplicatedStorage/Shared/Config/RoleConfig")

local giantRealmFolder = makeNode("GiantRealm")
addChild(giantRealmFolder, "SafeZonePolicy", "../../ReplicatedStorage/Shared/GiantRealm/SafeZonePolicy")
addChild(
	giantRealmFolder,
	"RemoteControlStationState",
	"../../ReplicatedStorage/Shared/GiantRealm/RemoteControlStationState"
)
addChild(
	giantRealmFolder,
	"GiantRealmResourceState",
	"../../ReplicatedStorage/Shared/GiantRealm/GiantRealmResourceState"
)

local sharedFolder = makeNode("Shared")
addChild(sharedFolder, "Config", configFolder)
addChild(sharedFolder, "GiantRealm", giantRealmFolder)

local replicatedStorage = makeNode("ReplicatedStorage", "ReplicatedStorage")
addChild(replicatedStorage, "Shared", sharedFolder)

local stationPart = makePart("GiantControlStation_A", { x = 0, y = 0, z = 0 }, { x = 8, y = 5, z = 6 }, {
	RemoteControlZoneId = "GiantControlZone_A",
})
local zonePart = makePart("GiantControlZone_A", { x = 0, y = 0, z = 0 }, { x = 60, y = 1, z = 60 })
addChild(zonePart, "Radius", { Name = "Radius", ClassName = "NumberValue", Value = 30 })

local routeAttributes = {
	RouteEnabled = true,
	TinyfolkOnlyRoute = true,
	TraversalGapBlockExempt = false,
	TraversalGapBlockState = "Idle",
	InSafeZone = false,
}
local routePart = makePart("EscapeRoute_A", { x = 6, y = 0, z = 0 }, { x = 10, y = 2, z = 10 }, routeAttributes)
local outsideRoutePart = makePart("EscapeRoute_Outside", { x = 80, y = 0, z = 0 }, { x = 10, y = 2, z = 10 }, {
	RouteEnabled = true,
	TinyfolkOnlyRoute = true,
	TraversalGapBlockExempt = false,
	TraversalGapBlockState = "Idle",
})

local stationsRoot = makeNode("Stations")
addChild(stationsRoot, "GiantControlStation_A", stationPart)
local zonesRoot = makeNode("ControlZones")
addChild(zonesRoot, "GiantControlZone_A", zonePart)
local routesRoot = makeNode("EscapeRoutes")
addChild(routesRoot, "EscapeRoute_A", routePart)
addChild(routesRoot, "EscapeRoute_Outside", outsideRoutePart)
local mapFolder = makeNode("Map")
addChild(mapFolder, "Stations", stationsRoot)
addChild(mapFolder, "ControlZones", zonesRoot)
addChild(mapFolder, "EscapeRoutes", routesRoot)
local workspaceService = makeNode("Workspace", "Workspace")
addChild(workspaceService, "Map", mapFolder)

local playersService = {
	GetPlayers = function()
		return {}
	end,
}

local fakeGame: any = {}
function fakeGame:GetService(serviceName: string): any
	if serviceName == "ReplicatedStorage" then
		return replicatedStorage
	end
	if serviceName == "Workspace" then
		return workspaceService
	end
	if serviceName == "Players" then
		return playersService
	end
	return nil
end

game = fakeGame
local currentTime = 100
local recordedEvents = {}
local ledgerAwards = {}
_G._GiantBuildModeService_QueryAPI = {
	GetRealmOwnerUserId = function()
		return 9402
	end,
	ApplyResourceAward = function(award: any): any
		table.insert(ledgerAwards, award)
		return { accepted = true, duplicate = false }
	end,
}
_G._EventLogService_QueryAPI = {
	RecordEvent = function(category: any, message: any, severity: any, timestamp: any, metadata: any): any
		table.insert(recordedEvents, {
			category = category,
			message = message,
			severity = severity,
			timestamp = timestamp,
			metadata = metadata,
		})
		return { accepted = true, reason = "accepted" }
	end,
}

local RemoteControlStationService =
	require("../src/ServerScriptService/Services/RemoteControlStationService.server")(fakeGame, {
		autoInitialize = true,
		clock = function()
			return currentTime
		end,
	})

local giant = MockPlayer.new(1, "GiantPlayer", { role = "Giant", positionZ = 0 })
local tinyfolk = MockPlayer.new(2, "TinyfolkPlayer", { role = "Tinyfolk", positionZ = 0 })

do
	local enter = RemoteControlStationService.requestEnter(giant, "GiantControlStation_A")
	assertTrue(enter.accepted, "Giant enters station")
	assertEqual(stationPart._Attributes.RemoteControlActiveOperatorUserId, 1, "station exposes active operator")

	local pressure = RemoteControlStationService.requestRoutePressure(giant, "GiantControlStation_A", "EscapeRoute_A")
	assertTrue(pressure.accepted, "Giant pressures in-zone route")
	assertEqual(routePart._Attributes.RemoteBarrierState, "Warning", "route exposes warning barrier")
	assertEqual(pressure.stationSnapshot.energy, 2, "pressure spends station energy")
	assertEqual(recordedEvents[#recordedEvents - 1].message, "remote route pressure accepted", "pressure emits event")
	assertEqual(#ledgerAwards, 1, "pressure awards defended raid resources")
	assertEqual(ledgerAwards[1].sourceKind, "defended_raid_route_pressure", "defended raid source kind")

	currentTime = 101
	assertTrue(RemoteControlStationService.isRouteRemoteBarrierActive("EscapeRoute_A"), "barrier becomes active")

	local repeated = RemoteControlStationService.requestRoutePressure(giant, "GiantControlStation_A", "EscapeRoute_A")
	assertFalse(repeated.accepted, "active remote barrier rejects repeat")
	assertEqual(repeated.reason, "remote_barrier_active", "active remote barrier repeat reason")

	currentTime = 105
	assertFalse(RemoteControlStationService.isRouteRemoteBarrierActive("EscapeRoute_A"), "barrier expires")
end

do
	currentTime = 200
	ledgerAwards = {}
	_G._VillageWorksiteUpgradeService_QueryAPI = {
		GetDefenseMultiplier = function(guardTowerId: string): number
			if guardTowerId == "GuardTower_A" then
				return 2
			end
			return 1
		end,
	}
	RemoteControlStationService.ResetForTests()

	local enter = RemoteControlStationService.requestEnter(giant, "GiantControlStation_A")
	assertTrue(enter.accepted, "guard tower defense enter accepted")

	local pressure = RemoteControlStationService.requestRoutePressure(giant, "GiantControlStation_A", "EscapeRoute_A")
	assertTrue(pressure.accepted, "guard tower defense pressure accepted")
	assertEqual(#ledgerAwards, 1, "guard tower defense awards treasury")
	assertEqual(ledgerAwards[1].essence, 6, "guard tower defense doubles essence")
	assertEqual(ledgerAwards[1].wood, 4, "guard tower defense doubles wood")
	assertEqual(ledgerAwards[1].stone, 2, "guard tower defense doubles stone")

	currentTime = 203
	assertTrue(
		RemoteControlStationService.isRouteRemoteBarrierActive("EscapeRoute_A"),
		"guard tower defense extends barrier active window"
	)

	currentTime = 211
	assertFalse(
		RemoteControlStationService.isRouteRemoteBarrierActive("EscapeRoute_A"),
		"guard tower defense barrier expires after extended duration"
	)
end

do
	currentTime = 110
	RemoteControlStationService.requestEnter(giant, "GiantControlStation_A")
	local outside =
		RemoteControlStationService.requestRoutePressure(giant, "GiantControlStation_A", "EscapeRoute_Outside")
	assertFalse(outside.accepted, "out-of-zone route rejects")
	assertEqual(outside.reason, "route_outside_control_zone", "out-of-zone reason")

	outsideRoutePart._Attributes.RouteEnabled = false
	local sealed = RemoteControlStationService.requestRoutePressure(giant, "GiantControlStation_A", "EscapeRoute_A")
	assertFalse(sealed.accepted, "last available route pressure rejects")
	assertEqual(sealed.reason, "would_seal_all_routes", "last available route pressure reason")
	outsideRoutePart._Attributes.RouteEnabled = true

	routeAttributes.TraversalGapBlockState = "Startup"
	local localBlock = RemoteControlStationService.requestRoutePressure(giant, "GiantControlStation_A", "EscapeRoute_A")
	assertFalse(localBlock.accepted, "local traversal block window rejects remote pressure")
	assertEqual(localBlock.reason, "traversal_gap_block_active", "local traversal block rejection reason")
	routeAttributes.TraversalGapBlockState = "Idle"

	routeAttributes.InSafeZone = true
	routeAttributes.SafeZoneType = "RealmExit"
	local protected = RemoteControlStationService.requestRoutePressure(giant, "GiantControlStation_A", "EscapeRoute_A")
	assertFalse(protected.accepted, "protected route rejects")
	assertEqual(protected.reason, "realm_exit_protected", "protected route reason")
	routeAttributes.InSafeZone = false
	routeAttributes.SafeZoneType = nil

	local nonGiant =
		RemoteControlStationService.requestRoutePressure(tinyfolk, "GiantControlStation_A", "EscapeRoute_A")
	assertFalse(nonGiant.accepted, "non-Giant pressure rejects")
	assertEqual(nonGiant.reason, "requester_not_giant", "non-Giant pressure reason")
end

do
	currentTime = 120
	local sabotage = RemoteControlStationService.requestSabotage(tinyfolk, "GiantControlStation_A")
	assertTrue(sabotage.accepted, "Tinyfolk sabotage accepts")
	assertEqual(sabotage.snapshot.lockoutEndsAt, 126, "sabotage applies lockout")
	assertEqual(sabotage.snapshot.activeOperatorUserId, nil, "sabotage clears operator")

	local lockedEnter = RemoteControlStationService.requestEnter(giant, "GiantControlStation_A")
	assertFalse(lockedEnter.accepted, "sabotage lockout rejects enter")
	assertEqual(lockedEnter.reason, "station_locked_out", "sabotage lockout reason")
	assertEqual(recordedEvents[#recordedEvents].message, "control station sabotaged", "sabotage emits event")

	currentTime = 127
	local snapshot = _G._RemoteControlStationService_QueryAPI.GetStationSnapshot("GiantControlStation_A")
	assertEqual(snapshot.stationId, "GiantControlStation_A", "query exposes station snapshot")
	assertTrue(
		type(_G._RemoteControlStationService_QueryAPI.GetAllStationSnapshots()) == "table",
		"query exposes all snapshots"
	)

	stationPart.Parent = nil
	stationsRoot._Children.GiantControlStation_A = nil
	local staleStation = _G._RemoteControlStationService_QueryAPI.GetStationSnapshot("GiantControlStation_A")
	assertEqual(staleStation, nil, "removed station is pruned from query snapshot")

	routePart.Parent = nil
	routesRoot._Children.EscapeRoute_A = nil
	local staleBarrier = _G._RemoteControlStationService_QueryAPI.GetRouteBarrierSnapshot("EscapeRoute_A")
	assertEqual(staleBarrier.state, "Idle", "removed route prunes stale barrier state")
end

print("remote_control_station_service_runtime_entrypoint: all checks passed")
