--!nocheck
--!nolint BuiltinGlobalWrite
-- selene: allow(global_usage)
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
		_Attributes = {},
	}

	function node.FindFirstChild(self: any, childName: string): any
		return self._Children[childName]
	end

	function node.WaitForChild(self: any, childName: string): any
		return self._Children[childName]
	end

	function node.GetChildren(self: any): { any }
		local children = {}
		for _, child in pairs(self._Children) do
			table.insert(children, child)
		end
		return children
	end

	function node.GetAttribute(self: any, attributeName: string): any
		return self._Attributes[attributeName]
	end

	function node.SetAttribute(self: any, attributeName: string, value: any)
		self._Attributes[attributeName] = value
	end

	return node
end

local function addChild(parent: any, childName: string, child: any)
	parent._Children[childName] = child
end

local replicatedStorage = makeNode("ReplicatedStorage", "ReplicatedStorage")
local sharedFolder = makeNode("Shared", "Folder")
local giantRealmFolder = makeNode("GiantRealm", "Folder")
addChild(giantRealmFolder, "TransportEscapeState", "../../ReplicatedStorage/Shared/GiantRealm/TransportEscapeState")
addChild(sharedFolder, "GiantRealm", giantRealmFolder)
addChild(replicatedStorage, "Shared", sharedFolder)

local workspaceService = makeNode("Workspace", "Workspace")
local mapFolder = makeNode("Map", "Folder")
local transportEndpointsFolder = makeNode("TransportEndpoints", "Folder")
local transportEndpointA = makeNode("TransportEndpoint_A", "Part")

transportEndpointA:SetAttribute("TransportEndpointId", "Transport_A")
transportEndpointA:SetAttribute("TransportRequiredComponents", { "Fuel", "Wheel" })
transportEndpointA:SetAttribute("TransportCapacity", 2)
transportEndpointA:SetAttribute("TransportOperatorRequired", true)
transportEndpointA:SetAttribute("TransportStartupDurationSeconds", 3)
transportEndpointA:SetAttribute("TransportLaunchDurationSeconds", 2)
transportEndpointA:SetAttribute("TransportMaxStartupInterruptions", 1)

addChild(transportEndpointsFolder, "TransportEndpoint_A", transportEndpointA)
addChild(mapFolder, "TransportEndpoints", transportEndpointsFolder)
addChild(workspaceService, "Map", mapFolder)

local fakeGame: any = {}
local playersList = {
	{
		UserId = 5001,
		GetAttribute = function(_self: any, attributeName: string): any
			if attributeName == "Role" then
				return "Tinyfolk"
			end
			return nil
		end,
	},
	{
		UserId = 5002,
		GetAttribute = function(_self: any, attributeName: string): any
			if attributeName == "Role" then
				return "Tinyfolk"
			end
			return nil
		end,
	},
	{
		UserId = 5003,
		GetAttribute = function(_self: any, attributeName: string): any
			if attributeName == "Role" then
				return "Tinyfolk"
			end
			return nil
		end,
	},
	{
		UserId = 6001,
		GetAttribute = function(_self: any, attributeName: string): any
			if attributeName == "Role" then
				return "Giant"
			end
			return nil
		end,
	},
}
local playersService: any = {}
function playersService:GetPlayers(): { any }
	return playersList
end
function fakeGame:GetService(serviceName: string): any
	if serviceName == "Players" then
		return playersService
	end
	if serviceName == "ReplicatedStorage" then
		return replicatedStorage
	end
	if serviceName == "Workspace" then
		return workspaceService
	end
	error("unsupported service " .. serviceName)
	return nil
end

local currentTime = 100
local escapeResolutionCalls = 0
local lastResolutionCandidates: { number } = {}
_G._EscapeService_QueryAPI = {
	ResolveTransportDeparture = function(_endpointId: string, candidateTinyfolkUserIds: { number }): any
		escapeResolutionCalls += 1
		lastResolutionCandidates = candidateTinyfolkUserIds
		return {
			accepted = true,
			reason = "accepted",
			escapedUserIds = { 5001, 5002 },
			safeReturnedUserIds = {},
			unresolvedUserIds = {},
		}
	end,
}
local TransportEscapeService = require("../src/ServerScriptService/Services/TransportEscapeService.server")
TransportEscapeService(fakeGame, {
	autoInitialize = true,
	clock = function()
		return currentTime
	end,
})

local queryApi: any = _G._TransportEscapeService_QueryAPI
assertTrue(type(queryApi) == "table", "transport escape service exposes query api")

local endpointIds = queryApi.GetTransportEndpointIds()
assertEqual(#endpointIds, 1, "startup discovers one transport endpoint")
assertEqual(endpointIds[1], "Transport_A", "startup discovered endpoint id")

local initialSnapshot = queryApi.GetTransportEndpointSnapshot("Transport_A")
assertEqual(initialSnapshot.phase, "Assembling", "initial phase is assembling")
assertFalse(initialSnapshot.assemblyReady, "initial assembly is not ready")
assertEqual(initialSnapshot.requiredComponentCount, 2, "initial required component count")
assertEqual(initialSnapshot.satisfiedRequiredCount, 0, "initial satisfied component count")

local deliveredFuel = queryApi.RecordTransportComponentDelivered("Transport_A", "Fuel", 5001, 101)
assertTrue(deliveredFuel.accepted, "component delivery accepted")
assertEqual(deliveredFuel.snapshot.satisfiedRequiredCount, 1, "delivery increases satisfied component count")

local installedWheel = queryApi.RecordTransportComponentInstalled("Transport_A", "Wheel", 5002, 102)
assertTrue(installedWheel.accepted, "component install accepted")
assertEqual(installedWheel.snapshot.phase, "Assembled", "all required components assemble endpoint")
assertTrue(installedWheel.snapshot.assemblyReady, "assembly ready after satisfying required components")

local boardOperator = queryApi.BoardTransportPassenger("Transport_A", 5001, true)
assertTrue(boardOperator.accepted, "operator boarding accepted")
assertEqual(boardOperator.snapshot.operatorUserId, 5001, "operator assignment persisted")

local boardPassenger = queryApi.BoardTransportPassenger("Transport_A", 5002, false)
assertTrue(boardPassenger.accepted, "passenger boarding accepted")
assertEqual(boardPassenger.snapshot.boardedCount, 2, "board count increments for passenger")

local overCapacity = queryApi.BoardTransportPassenger("Transport_A", 5003, false)
assertFalse(overCapacity.accepted, "boarding over capacity rejected")
assertEqual(overCapacity.reason, "transport_full", "over-capacity reason projected")

local startup = queryApi.StartTransportStartup("Transport_A", 5001, 110)
assertTrue(startup.accepted, "startup accepted")
assertEqual(startup.snapshot.phase, "Startup", "startup phase entered")
assertEqual(startup.snapshot.startupEndsAt, 113, "startup end timestamp from duration")

local interrupted = queryApi.InterruptTransportStartup("Transport_A", 111)
assertTrue(interrupted.accepted, "first startup interruption accepted")
assertEqual(interrupted.snapshot.phase, "Boarding", "interruption returns phase to boarding")

local restart = queryApi.StartTransportStartup("Transport_A", 5001, 120)
assertTrue(restart.accepted, "startup can restart after interruption")

local secondInterrupt = queryApi.InterruptTransportStartup("Transport_A", 121)
assertFalse(secondInterrupt.accepted, "startup interruption bound enforced")
assertEqual(secondInterrupt.reason, "interrupt_limit_reached", "startup interruption bound reason")

local launchTick = queryApi.TickTransportEndpoint("Transport_A", 123)
assertTrue(launchTick.accepted, "startup->launch transition accepted")
assertEqual(launchTick.reason, "launch_started", "startup->launch reason")
assertEqual(launchTick.snapshot.phase, "Launched", "phase transitions to launched")

local departTick = queryApi.TickTransportEndpoint("Transport_A", 125)
assertTrue(departTick.accepted, "launch->depart transition accepted")
assertEqual(departTick.reason, "departed", "launch->depart reason")
assertEqual(departTick.snapshot.phase, "Departed", "phase transitions to departed")
assertTrue(type(departTick.escapeResolution) == "table", "depart tick includes escape resolution payload")
assertEqual(departTick.escapeResolution.accepted, true, "depart tick escape resolution accepted")
assertEqual(escapeResolutionCalls, 1, "depart triggers escape resolution integration exactly once")
assertEqual(#lastResolutionCandidates, 2, "depart integration collects only transport participants")
assertEqual(lastResolutionCandidates[1], 5001, "depart integration candidate list starts with boarded operator")
assertEqual(lastResolutionCandidates[2], 5002, "depart integration candidate list excludes unrelated bystander")

local departureOutcome = queryApi.ResolveTransportDepartureOutcome("Transport_A", { 5001, 5002, 5003 })
assertTrue(departureOutcome.accepted, "departure outcome resolves after depart")
assertEqual(#departureOutcome.outcome.boardedEscapedUserIds, 2, "departure boarded escaped count")
assertEqual(#departureOutcome.outcome.unboardedRemainingUserIds, 1, "departure unboarded count")

local unknownEndpoint = queryApi.GetTransportEndpointSnapshot("MissingEndpoint")
assertTrue(unknownEndpoint == nil, "unknown endpoint snapshot is nil")

workspaceService._Children["Map"] = nil
queryApi.ResetForTests()
local afterResetIds = queryApi.GetTransportEndpointIds()
assertEqual(#afterResetIds, 0, "missing workspace path reset yields zero endpoints")

print("transport_escape_service_runtime_entrypoint: all checks passed")
