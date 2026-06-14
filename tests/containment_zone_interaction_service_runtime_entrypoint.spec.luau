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

local function makeSignal()
	local callbacks: { (any) -> () } = {}
	return {
		Connect = function(_self: any, callback: (any) -> ())
			table.insert(callbacks, callback)
			return {}
		end,
	}
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
	return node
end

local function addChild(parent: any, childName: string, child: any)
	parent._Children[childName] = child
end

local configFolder = makeNode("Config")
addChild(configFolder, "CaptureConfig", "../../ReplicatedStorage/Shared/Config/CaptureConfig")
addChild(configFolder, "RoleConfig", "../../ReplicatedStorage/Shared/Config/RoleConfig")
addChild(
	configFolder,
	"ContainmentStructureConfig",
	"../../ReplicatedStorage/Shared/Config/ContainmentStructureConfig"
)

local giantRealmFolder = makeNode("GiantRealm")
addChild(giantRealmFolder, "CaptivityDurationState", "../../ReplicatedStorage/Shared/GiantRealm/CaptivityDurationState")
addChild(
	giantRealmFolder,
	"CapturePersistenceRules",
	"../../ReplicatedStorage/Shared/GiantRealm/CapturePersistenceRules"
)
addChild(
	giantRealmFolder,
	"ContainmentZoneEscapeState",
	"../../ReplicatedStorage/Shared/GiantRealm/ContainmentZoneEscapeState"
)

local sharedFolder = makeNode("Shared")
addChild(sharedFolder, "Config", configFolder)
addChild(sharedFolder, "GiantRealm", giantRealmFolder)

local replicatedStorage = makeNode("ReplicatedStorage")
addChild(replicatedStorage, "Shared", sharedFolder)

local playersList: { any } = {}
local playersService: any = {
	PlayerRemoving = makeSignal(),
}
function playersService:GetPlayers(): { any }
	return playersList
end

local fakeGame: any = {}
function fakeGame:GetService(serviceName: string): any
	if serviceName == "Players" then
		return playersService
	end
	if serviceName == "ReplicatedStorage" then
		return replicatedStorage
	end
	return {
		GetPlayers = function()
			return {}
		end,
	}
end

game = fakeGame

local captureRecords: { [number]: any } = {}
local custodyEndCalls: { any } = {}
local promoteCalls: { any } = {}
local suppressionCalls: { any } = {}
local structureOccupants: { [number]: boolean } = {}

_G._CaptureService_QueryAPI = {
	GetTargetCapture = function(targetUserId: number, _at: number?): any
		return captureRecords[targetUserId]
	end,
	CanTargetPerformEscapeAction = function(_action: string): boolean
		return true
	end,
	ResolveCustodyEnd = function(targetUserId: number, endReason: string, at: number?, _operationId: string?): any
		table.insert(custodyEndCalls, {
			targetUserId = targetUserId,
			endReason = endReason,
			at = at,
		})
		captureRecords[targetUserId] = nil
		structureOccupants[targetUserId] = nil
		return { accepted = true, reason = endReason }
	end,
	PromoteTargetToContained = function(targetUserId: number, at: number?): any
		local record = captureRecords[targetUserId]
		if record == nil then
			return { accepted = false, reason = "capture_missing" }
		end
		record.containmentPhase = "contained"
		record.containedAt = at
		structureOccupants[targetUserId] = true
		table.insert(promoteCalls, { targetUserId = targetUserId, at = at })
		return { accepted = true, reason = "contained", record = record, structureId = "ContainmentStructure_A" }
	end,
}

_G._ContainmentStructureService_QueryAPI = {
	HasEscapeInteractionForTarget = function(targetUserId: number): boolean
		return structureOccupants[targetUserId] == true
	end,
	GetStructureIdForTargetUserId = function(targetUserId: number): string?
		if structureOccupants[targetUserId] == true then
			return "ContainmentStructure_A"
		end
		return nil
	end,
	CanRescueOccupant = function(rescuerUserId: number, targetUserId: number, _position: any): any
		if structureOccupants[targetUserId] ~= true then
			return { accepted = false, reason = "occupant_not_found" }
		end
		if rescuerUserId == targetUserId then
			return { accepted = false, reason = "self_rescue_not_allowed" }
		end
		return { accepted = true, reason = "accepted", structureId = "ContainmentStructure_A" }
	end,
	EvaluateCaptureDeliveryEligibility = function(input: any): any
		if type(input) ~= "table" then
			return { eligible = false, reason = "delivery_input_invalid" }
		end
		local giantPosition = input.custodianPosition or input.giantPosition
		if type(giantPosition) == "table" and giantPosition.x == 55 then
			return { eligible = true, reason = "accepted", structureId = "ContainmentStructure_A" }
		end
		return { eligible = false, reason = "containment_structure_not_in_range" }
	end,
}

_G._CaptivityEscapeService_QueryAPI = {
	TryApplyContainmentSuppression = function(targetUserId: number, at: number?): any
		table.insert(suppressionCalls, { targetUserId = targetUserId, at = at })
		return { accepted = false, reason = "already_contained" }
	end,
}

local ContainmentZoneInteractionService =
	require("../src/ServerScriptService/Services/ContainmentZoneInteractionService.server")(
		fakeGame,
		{ disableRemotes = true }
	)

local interactionApi = _G._ContainmentZoneInteractionService_QueryAPI
assertTrue(type(interactionApi) == "table", "interaction query api exposed")

local function makePlayer(userId: number, role: string, position: { x: number, y: number, z: number }): any
	local player = MockPlayer.new(userId, "Player" .. tostring(userId))
	player:SetAttribute("Role", role)
	player.Character = {
		FindFirstChild = function(_self: any, name: string): any
			if name == "HumanoidRootPart" then
				return {
					Position = position,
					IsA = function(_part: any, className: string): boolean
						return className == "BasePart"
					end,
				}
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
	table.insert(playersList, player)
	return player
end

local function resetRuntime()
	playersList = {}
	captureRecords = {}
	custodyEndCalls = {}
	promoteCalls = {}
	suppressionCalls = {}
	structureOccupants = {}
	interactionApi.ResetForTests()
end

do
	resetRuntime()
	local contained = makePlayer(5001, "Tinyfolk", { x = 55, y = 2, z = -87 })
	makePlayer(5002, "Giant", { x = 55, y = 2, z = -85 })
	captureRecords[5001] = {
		custodianUserId = 5002,
		targetUserId = 5001,
		containmentPhase = "contained",
	}
	structureOccupants[5001] = true

	local lastResult = interactionApi.RequestContainedEscape(5001, 1)
	assertTrue(lastResult.accepted, "first contained escape action accepts")
	assertEqual(lastResult.snapshot.progress, 1, "first contained escape progress")

	for step = 2, 5 do
		lastResult = interactionApi.RequestContainedEscape(5001, step)
	end
	assertTrue(lastResult.completed == true or lastResult.reason == "contained_escape_completed", "contained escape completes")
	assertEqual(#custodyEndCalls, 1, "contained escape ends custody once")
	assertEqual(custodyEndCalls[1].endReason, "released", "contained escape release reason")
end

do
	resetRuntime()
	local contained = makePlayer(5101, "Tinyfolk", { x = 55, y = 2, z = -87 })
	makePlayer(5102, "Giant", { x = 55, y = 2, z = -85 })
	local rescuer = makePlayer(5103, "Tinyfolk", { x = 55, y = 2, z = -84 })
	captureRecords[5101] = {
		custodianUserId = 5102,
		targetUserId = 5101,
		containmentPhase = "contained",
	}
	structureOccupants[5101] = true

	local rescue = interactionApi.RequestStructureRescue(5103, 5101, 2)
	assertTrue(rescue.accepted, "structure rescue accepts")
	assertEqual(rescue.reason, "structure_rescue_completed", "structure rescue reason")
	assertEqual(#custodyEndCalls, 1, "structure rescue ends custody")
	assertEqual(custodyEndCalls[1].endReason, "rescued", "structure rescue custody end reason")
end

do
	resetRuntime()
	makePlayer(5201, "Tinyfolk", { x = 55, y = 2, z = -87 })
	makePlayer(5202, "Giant", { x = 55, y = 2, z = -85 })
	captureRecords[5201] = {
		custodianUserId = 5202,
		targetUserId = 5201,
		containmentPhase = "captured",
	}

	local delivery = interactionApi.TryDeliverGrabPlacement({
		giantUserId = 5202,
		targetUserId = 5201,
		giantPosition = { x = 55, y = 2, z = -85 },
		targetPosition = { x = 55, y = 2, z = -87 },
		at = 3,
	})
	assertTrue(delivery.accepted, "grab placement delivery accepts in structure zone")
	assertEqual(delivery.reason, "grab_place_containment_delivered", "grab placement delivery reason")
	assertEqual(#promoteCalls, 1, "grab placement promotes to contained")
	assertEqual(#suppressionCalls, 1, "grab placement applies suppression")
end

do
	resetRuntime()
	makePlayer(5301, "Tinyfolk", { x = 0, y = 0, z = 0 })
	makePlayer(5302, "Giant", { x = 1, y = 0, z = 1 })
	captureRecords[5301] = {
		custodianUserId = 5302,
		targetUserId = 5301,
		containmentPhase = "captured",
	}

	local delivery = interactionApi.TryDeliverGrabPlacement({
		giantUserId = 5302,
		targetUserId = 5301,
		giantPosition = { x = 0, y = 0, z = 0 },
		targetPosition = { x = 1, y = 0, z = 1 },
		at = 3,
	})
	assertFalse(delivery.accepted, "grab placement delivery rejects out of zone")
	assertEqual(delivery.reason, "containment_structure_not_in_range", "out of zone reason")
end

print("containment_zone_interaction_service_runtime_entrypoint: all checks passed")
