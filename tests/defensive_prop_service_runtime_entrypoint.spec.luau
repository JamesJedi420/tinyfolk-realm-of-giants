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
addChild(configFolder, "DefensivePropConfig", "../../ReplicatedStorage/Shared/Config/DefensivePropConfig")
addChild(configFolder, "EscapeConfig", "../../ReplicatedStorage/Shared/Config/EscapeConfig")
addChild(configFolder, "RoleConfig", "../../ReplicatedStorage/Shared/Config/RoleConfig")

local giantRealmFolder = makeNode("GiantRealm")
addChild(giantRealmFolder, "DefensivePropState", "../../ReplicatedStorage/Shared/GiantRealm/DefensivePropState")

local sharedFolder = makeNode("Shared")
addChild(sharedFolder, "Config", configFolder)
addChild(sharedFolder, "GiantRealm", giantRealmFolder)

local replicatedStorage = makeNode("ReplicatedStorage", "ReplicatedStorage")
addChild(replicatedStorage, "Shared", sharedFolder)

local propPart = makePart("DefensiveProp_A", { x = 0, y = 0, z = 0 }, { x = 6, y = 4, z = 2 }, {
	DefensivePropType = "crate",
	DefensivePropZoneId = "DefensivePropZone_A",
	DefensivePropEnabled = true,
})
local zonePart = makePart("DefensivePropZone_A", { x = 0, y = 0, z = 0 }, { x = 52, y = 1, z = 52 })
addChild(zonePart, "Radius", { Name = "Radius", ClassName = "NumberValue", Value = 26 })

local giantRoutePart = makePart("GiantRoute_PlazaToHearth", { x = 0, y = 0, z = -10 }, { x = 18, y = 1, z = 72 }, {
	GiantOnlyRoute = true,
	TinyfolkOnlyRoute = false,
	RouteEnabled = true,
	RouteType = "GiantMacro",
	RoadKind = "GiantMacro",
})

local propsRoot = makeNode("DefensiveProps")
addChild(propsRoot, "DefensiveProp_A", propPart)
local zonesRoot = makeNode("DefensivePropZones")
addChild(zonesRoot, "DefensivePropZone_A", zonePart)
local giantRoutesRoot = makeNode("GiantRoutes")
addChild(giantRoutesRoot, "GiantRoute_PlazaToHearth", giantRoutePart)
local mapFolder = makeNode("Map")
addChild(mapFolder, "DefensiveProps", propsRoot)
addChild(mapFolder, "DefensivePropZones", zonesRoot)
addChild(mapFolder, "GiantRoutes", giantRoutesRoot)
local workspaceService = makeNode("Workspace", "Workspace")
addChild(workspaceService, "Map", mapFolder)

local fakeGame: any = {}
function fakeGame:GetService(serviceName: string): any
	if serviceName == "ReplicatedStorage" then
		return replicatedStorage
	end
	if serviceName == "Workspace" then
		return workspaceService
	end
	return {
		GetPlayers = function()
			return {}
		end,
	}
end

game = fakeGame
local currentTime = 100
local recordedEvents = {}
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

local DefensivePropService = require("../src/ServerScriptService/Services/DefensivePropService.server")(fakeGame, {
	now = function()
		return currentTime
	end,
	disableScheduling = true,
})

local tinyfolk = MockPlayer.new(4201, "TinyfolkRunner", { Role = "Tinyfolk" })
tinyfolk.Character = {
	FindFirstChild = function(_self: any, childName: string): any
		if childName == "HumanoidRootPart" then
			return { Position = { x = 0, y = 0, z = 0 } }
		end
		return nil
	end,
	FindFirstChildOfClass = function(_self: any, className: string): any
		if className == "Humanoid" then
			return { Health = 100 }
		end
		return nil
	end,
}

local giant = MockPlayer.new(9001, "GiantBreaker", { Role = "Giant" })
giant.Character = tinyfolk.Character

do
	local drop = DefensivePropService.requestDrop(tinyfolk, "DefensiveProp_A")
	assertTrue(drop.accepted, "Tinyfolk drop accepts")
	assertEqual(drop.snapshot.state, "Dropped", "drop projects Dropped state")
	assertEqual(recordedEvents[#recordedEvents].message, "defensive prop dropped", "drop emits event")
	assertFalse(
		DefensivePropService.isGiantMacroRouteBlocked("GiantRoute_PlazaToHearth"),
		"startup phase does not block giant macro route"
	)

	currentTime = 102
	assertTrue(
		DefensivePropService.isGiantMacroRouteBlocked("GiantRoute_PlazaToHearth"),
		"active phase blocks giant macro route in zone"
	)
	assertEqual(
		DefensivePropService.getGiantMacroRouteBlockReason("GiantRoute_PlazaToHearth"),
		"defensive_prop_blocked",
		"block reason is deterministic"
	)
end

do
	currentTime = 103
	local startBreak = DefensivePropService.requestStartBreak(giant, "DefensiveProp_A")
	assertTrue(startBreak.accepted, "Giant break start accepts")
	assertTrue(startBreak.snapshot.breakInProgress, "break start marks in-progress window")

	local earlyComplete = DefensivePropService.requestCompleteBreak(giant, "DefensiveProp_A")
	assertFalse(earlyComplete.accepted, "early break completion rejects")
	assertEqual(earlyComplete.reason, "break_in_progress", "early break reason")

	currentTime = 105
	local complete = DefensivePropService.requestCompleteBreak(giant, "DefensiveProp_A")
	assertTrue(complete.accepted, "completed break accepts")
	assertEqual(complete.snapshot.state, "Broken", "completed break projects Broken")
	assertFalse(
		DefensivePropService.isGiantMacroRouteBlocked("GiantRoute_PlazaToHearth"),
		"broken prop stops blocking giant macro route"
	)
	assertEqual(recordedEvents[#recordedEvents].message, "defensive prop broken", "break emits event")
end

do
	DefensivePropService.ResetForTests()
	currentTime = 200
	local nonGiant = DefensivePropService.requestDrop(giant, "DefensiveProp_A")
	assertFalse(nonGiant.accepted, "Giant drop rejects")
	assertEqual(nonGiant.reason, "requester_not_tinyfolk", "Giant drop reason")

	local tinyfolkBreak = DefensivePropService.requestStartBreak(tinyfolk, "DefensiveProp_A")
	assertFalse(tinyfolkBreak.accepted, "Tinyfolk break rejects")
	assertEqual(tinyfolkBreak.reason, "requester_not_giant", "Tinyfolk break reason")
end

print("defensive_prop_service_runtime_entrypoint: all checks passed")
