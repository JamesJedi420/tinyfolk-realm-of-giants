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
	local callbacks: { (Player) -> () } = {}
	return {
		Connect = function(_self: any, callback: (Player) -> ())
			table.insert(callbacks, callback)
			return {}
		end,
		Fire = function(_self: any, player: Player)
			for _, callback in ipairs(callbacks) do
				callback(player)
			end
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

	function node.FindFirstChild(self: any, childName: string): any
		return self._Children[childName]
	end

	function node.WaitForChild(self: any, childName: string): any
		return self._Children[childName]
	end

	function node.GetDescendants(_self: any): { any }
		local descendants: { any } = {}
		local function walk(current: any)
			for _, child in pairs(current._Children) do
				table.insert(descendants, child)
				walk(child)
			end
		end
		walk(node)
		return descendants
	end

	return node
end

local function addChild(parent: any, childName: string, child: any)
	parent._Children[childName] = child
end

local function makeRemoteEvent(remoteName: string)
	local remote: any = {
		Name = remoteName,
		ClassName = "RemoteEvent",
		_Handler = nil,
	}

	function remote:IsA(expectedClass: string): boolean
		return self.ClassName == expectedClass
	end

	remote.OnServerEvent = {
		Connect = function(_signal: any, handler: (any, any) -> ())
			remote._Handler = handler
		end,
	}

	return remote
end

local remotesFolder = makeNode("Remotes", "Folder")
addChild(remotesFolder, "CaptivityStruggleRequest", makeRemoteEvent("CaptivityStruggleRequest"))
addChild(remotesFolder, "CaptivityAllyAssistRequest", makeRemoteEvent("CaptivityAllyAssistRequest"))

local configFolder = makeNode("Config", "Folder")
addChild(configFolder, "CaptureConfig", "../../ReplicatedStorage/Shared/Config/CaptureConfig")
addChild(configFolder, "RoleConfig", "../../ReplicatedStorage/Shared/Config/RoleConfig")

local giantRealmFolder = makeNode("GiantRealm", "Folder")
addChild(
	giantRealmFolder,
	"CaptivityEscapeProgressState",
	"../../ReplicatedStorage/Shared/GiantRealm/CaptivityEscapeProgressState"
)
addChild(giantRealmFolder, "CaptivityDurationState", "../../ReplicatedStorage/Shared/GiantRealm/CaptivityDurationState")
addChild(
	giantRealmFolder,
	"CapturePersistenceRules",
	"../../ReplicatedStorage/Shared/GiantRealm/CapturePersistenceRules"
)

local sharedFolder = makeNode("Shared", "Folder")
addChild(sharedFolder, "Config", configFolder)
addChild(sharedFolder, "GiantRealm", giantRealmFolder)

local replicatedStorage = makeNode("ReplicatedStorage", "ReplicatedStorage")
addChild(replicatedStorage, "Shared", sharedFolder)
addChild(replicatedStorage, "Remotes", remotesFolder)

local captureZonesFolder = makeNode("CaptureZones", "Folder")
local containmentZone: any = {
	Name = "GiantCaptureZone_A",
	ClassName = "Part",
	_Children = {},
	Size = { x = 40, y = 4, z = 24 },
	Position = { x = 55, y = 0.55, z = -78 },
}
function containmentZone:IsA(className: string): boolean
	return className == "BasePart"
end
function containmentZone:GetDescendants(): { any }
	return {}
end

addChild(captureZonesFolder, "GiantCaptureZone_A", containmentZone)

local mapFolder = makeNode("Map", "Folder")
addChild(mapFolder, "CaptureZones", captureZonesFolder)

local workspace = makeNode("Workspace", "Workspace")
addChild(workspace, "Map", mapFolder)

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
	if serviceName == "Workspace" then
		return workspace
	end
	error("unsupported service " .. serviceName)
	return nil
end

game = fakeGame

local captureRecords: { [number]: any } = {}
local custodyEndCalls: { any } = {}
local promoteCalls: { any } = {}

local function resetCaptureRuntime()
	captureRecords = {}
	custodyEndCalls = {}
	promoteCalls = {}
end

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
		return { accepted = true, reason = endReason }
	end,
	PromoteTargetToContained = function(targetUserId: number, at: number?): any
		local record = captureRecords[targetUserId]
		if record == nil then
			return { accepted = false, reason = "capture_missing" }
		end
		record.containmentPhase = "contained"
		record.containedAt = at
		table.insert(promoteCalls, { targetUserId = targetUserId, at = at })
		return { accepted = true, reason = "contained", record = record }
	end,
}

require("../src/ServerScriptService/Services/CaptivityEscapeService.server")

local escapeApi = _G._CaptivityEscapeService_QueryAPI
assertTrue(type(escapeApi) == "table", "captivity escape query api exposed")

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

local function resetPlayers()
	playersList = {}
	escapeApi.ResetForTests()
	resetCaptureRuntime()
end

resetPlayers()
local _captured = makePlayer(3001, "Tinyfolk", { x = 0, y = 0, z = 0 })
local _custodian = makePlayer(3002, "Giant", { x = 100, y = 0, z = 100 })
captureRecords[3001] = {
	custodianUserId = 3002,
	targetUserId = 3001,
	startedAt = 1,
	expiresAt = 9,
	captivityAnchorAt = 1,
	containmentPhase = "captured",
}

local struggle1 = escapeApi.RequestStruggle(3001, 2.0)
assertTrue(struggle1.accepted, "first struggle accepted")
assertEqual(struggle1.snapshot.progress, 1, "first struggle progress")

local struggle2 = escapeApi.RequestStruggle(3001, 2.4)
assertTrue(struggle2.accepted, "second struggle accepted")
assertEqual(struggle2.snapshot.progress, 2, "second struggle progress")

local _ally = makePlayer(3003, "Tinyfolk", { x = 5, y = 0, z = 0 })
local assist = escapeApi.RequestAllyAssist(3003, 3001, 3.0)
assertTrue(assist.accepted, "ally assist accepted")
assertEqual(assist.snapshot.progress, 3, "ally assist progress")

assertEqual(escapeApi.CountNearbyRescueAllies(3001, 3.4), 1, "nearby ally counted")
local allyBoost = escapeApi.RequestStruggle(3001, 3.4)
assertTrue(allyBoost.accepted, "struggle with ally nearby accepted")
assertEqual(allyBoost.reason, "struggle_escape_completed", "struggle completion reason")
assertEqual(#custodyEndCalls, 1, "custody end on completion")
assertEqual(custodyEndCalls[1].endReason, "released", "struggle release reason")

resetPlayers()
local _decayTarget = makePlayer(3101, "Tinyfolk", { x = 0, y = 0, z = 0 })
makePlayer(3102, "Giant", { x = 100, y = 0, z = 100 })
captureRecords[3101] = {
	custodianUserId = 3102,
	targetUserId = 3101,
	startedAt = 1,
	expiresAt = 9,
	captivityAnchorAt = 1,
	containmentPhase = "captured",
}
escapeApi.RequestStruggle(3101, 1.0)
local beforeDecay = escapeApi.GetProgressSnapshot(3101, 1.0)
assertEqual(beforeDecay.progress, 1, "progress before decay")
local afterDecay = escapeApi.GetProgressSnapshot(3101, 4.0)
assertEqual(afterDecay.progress, 0, "progress decays after idle window")

resetPlayers()
local _suppressTarget = makePlayer(3201, "Tinyfolk", { x = 55, y = 0.55, z = -78 })
makePlayer(3202, "Giant", { x = 55, y = 0.55, z = -78 })
captureRecords[3201] = {
	custodianUserId = 3202,
	targetUserId = 3201,
	startedAt = 1,
	expiresAt = 9,
	captivityAnchorAt = 1,
	containmentPhase = "captured",
}
escapeApi.RequestStruggle(3201, 1.0)
escapeApi.RequestStruggle(3201, 1.4)
local suppressed = escapeApi.TryApplyContainmentSuppression(3201, 2.0)
assertTrue(suppressed.accepted, "containment suppression accepted")
assertEqual(suppressed.reason, "containment_suppressed", "suppression reason")
assertEqual(#promoteCalls, 1, "promote to contained called")
assertEqual(suppressed.snapshot.progress, 0, "suppression clears progress")
assertTrue(suppressed.snapshot.suppressed, "suppression flag set")

local blocked = escapeApi.RequestStruggle(3201, 2.5)
assertFalse(blocked.accepted, "suppressed struggle rejected")
assertEqual(blocked.reason, "escape_suppressed_contained", "suppressed struggle reason")

print("captivity_escape_service_runtime_entrypoint: all checks passed")
