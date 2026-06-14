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
		_ClientPayloads = {},
	}

	function remote:IsA(expectedClass: string): boolean
		return self.ClassName == expectedClass
	end

	remote.OnServerEvent = {
		Connect = function(_signal: any, handler: (any, any) -> ())
			remote._Handler = handler
		end,
	}

	function remote:FireClient(player: any, payload: any)
		table.insert(self._ClientPayloads, {
			userId = player.UserId,
			payload = payload,
		})
	end

	return remote
end

local remotesFolder = makeNode("Remotes", "Folder")
addChild(remotesFolder, "CustodyTransferRequest", makeRemoteEvent("CustodyTransferRequest"))
addChild(remotesFolder, "CustodyTransferConfirm", makeRemoteEvent("CustodyTransferConfirm"))
addChild(remotesFolder, "CustodyTransferCancel", makeRemoteEvent("CustodyTransferCancel"))
addChild(remotesFolder, "CustodyTransferNotify", makeRemoteEvent("CustodyTransferNotify"))

local configFolder = makeNode("Config", "Folder")
addChild(configFolder, "CaptureConfig", "../../ReplicatedStorage/Shared/Config/CaptureConfig")
addChild(configFolder, "CustodyTransferConfig", "../../ReplicatedStorage/Shared/Config/CustodyTransferConfig")
addChild(configFolder, "PenRationingConfig", "../../ReplicatedStorage/Shared/Config/PenRationingConfig")
addChild(configFolder, "StationConfig", "../../ReplicatedStorage/Shared/Config/StationConfig")
addChild(
	configFolder,
	"VillageWorksiteUpgradeConfig",
	"../../ReplicatedStorage/Shared/Config/VillageWorksiteUpgradeConfig"
)

local giantRealmFolder = makeNode("GiantRealm", "Folder")
addChild(giantRealmFolder, "CaptureState", "../../ReplicatedStorage/Shared/GiantRealm/CaptureState")
addChild(giantRealmFolder, "CaptivityDurationState", "../../ReplicatedStorage/Shared/GiantRealm/CaptivityDurationState")
addChild(giantRealmFolder, "CustodyTransferState", "../../ReplicatedStorage/Shared/GiantRealm/CustodyTransferState")
addChild(
	giantRealmFolder,
	"CapturePersistenceRules",
	"../../ReplicatedStorage/Shared/GiantRealm/CapturePersistenceRules"
)
addChild(
	giantRealmFolder,
	"DisconnectResolutionState",
	"../../ReplicatedStorage/Shared/GiantRealm/DisconnectResolutionState"
)
addChild(
	giantRealmFolder,
	"PostRescueProtectionState",
	"../../ReplicatedStorage/Shared/GiantRealm/PostRescueProtectionState"
)
addChild(giantRealmFolder, "PenRationingState", "../../ReplicatedStorage/Shared/GiantRealm/PenRationingState")
addChild(
	giantRealmFolder,
	"VillageWorksiteUpgradeState",
	"../../ReplicatedStorage/Shared/GiantRealm/VillageWorksiteUpgradeState"
)

local sharedFolder = makeNode("Shared", "Folder")
addChild(sharedFolder, "Config", configFolder)
addChild(sharedFolder, "GiantRealm", giantRealmFolder)

local replicatedStorage = makeNode("ReplicatedStorage", "ReplicatedStorage")
addChild(replicatedStorage, "Shared", sharedFolder)
addChild(replicatedStorage, "Remotes", remotesFolder)

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
	error("unsupported service " .. serviceName)
	return nil
end

game = fakeGame

local eventLogCalls: { any } = {}
_G._ProfilePersistenceGateway_QueryAPI = {
	UpdateLoadedPlayerProfileData = function(_player: any, updater: any): any
		return { ok = true, data = updater({}) }
	end,
}
_G._ScoreService_QueryAPI = {
	RequestScoreEvent = function(): any
		return { accepted = true, reason = "accepted", awardedPoints = 0 }
	end,
}
_G._EscapeService_QueryAPI = {
	ApplyCaptivitySafeReturn = function(): any
		return { accepted = true, reason = "safe_return_applied" }
	end,
}
_G._RuntimeEventLogService_QueryAPI = {
	RecordEvent = function(payload: any): any
		table.insert(eventLogCalls, payload)
		return { accepted = true }
	end,
}

require("../src/ServerScriptService/Services/CaptureService.server")
require("../src/ServerScriptService/Services/CustodyTransferService.server")

local captureApi: any = _G._CaptureService_QueryAPI
local transferApi: any = _G._CustodyTransferService_QueryAPI
assertTrue(type(captureApi) == "table", "capture api exposed")
assertTrue(type(transferApi) == "table", "custody transfer api exposed")

local giantA = MockPlayer.new(3101, "GiantA", {
	role = "Giant",
	positionZ = 0,
	health = 100,
})
local giantB = MockPlayer.new(3105, "GiantB", {
	role = "Giant",
	positionZ = 1,
	health = 100,
})
local target = MockPlayer.new(3102, "Target", {
	role = "Tinyfolk",
	positionZ = 0,
	health = 100,
})

playersList = { giantA, giantB, target }

local function setDowned(player: any, value: boolean)
	player:SetAttribute("DownedIsDowned", value)
end

local function resetState()
	captureApi.ResetForTests()
	transferApi.ResetForTests()
	eventLogCalls = {}
	setDowned(target, true)
end

resetState()
local capture = captureApi.RequestCapture(3101, 3102, 1.0)
assertTrue(capture.accepted == true, "baseline capture accepted")

local requested = transferApi.RequestCustodyTransfer(3101, 3102, 3105, 2.0)
assertTrue(requested.accepted == true, "transfer request accepted")
assertTrue(type(requested.request) == "table", "transfer request returned")
assertEqual(requested.request.terms.captivityAnchorAt, 1.0, "request terms preserve anchor")
assertEqual(requested.request.terms.custodyExpiresAt, 9.0, "request terms preserve custody window")
assertTrue(#requested.request.terms.endConditions >= 4, "request terms expose end conditions")
assertEqual(target:GetAttribute("CustodyTransferPendingRequestId"), requested.request.requestId, "target pending id")
assertEqual(target:GetAttribute("CustodyTransferTermsCaptivityAnchorAt"), 1.0, "target terms anchor attribute")

local pending = transferApi.GetPendingTransferForTarget(3102, 2.5)
assertTrue(pending ~= nil, "pending transfer queryable")
assertEqual(pending.terms.incomingCustodianUserId, 3105, "pending incoming custodian")

local confirmed = transferApi.ConfirmCustodyTransfer(3105, requested.request.requestId, 3.0)
assertTrue(confirmed.accepted == true, "transfer confirm accepted")
assertEqual(confirmed.reason, "custody_transferred", "transfer confirm reason")
assertEqual(confirmed.record.custodianUserId, 3105, "capture custodian updated")
assertEqual(confirmed.record.captivityAnchorAt, 1.0, "settled capture preserves anchor")
assertEqual(confirmed.record.startedAt, 1.0, "settled capture preserves startedAt")

local active = captureApi.GetTargetCapture(3102, 4.0)
assertTrue(active ~= nil, "capture remains active after transfer")
assertEqual(active.custodianUserId, 3105, "active capture reflects new custodian")
assertTrue(transferApi.GetPendingTransferForTarget(3102, 4.0) == nil, "pending cleared after settle")
assertEqual(#eventLogCalls, 2, "request and settle logged")

resetState()
captureApi.RequestCapture(3101, 3102, 1.0)
local requestAgain = transferApi.RequestCustodyTransfer(3101, 3102, 3105, 2.0)
assertTrue(requestAgain.accepted == true, "cancel setup request accepted")
local cancelled = transferApi.CancelCustodyTransfer(3101, requestAgain.request.requestId, 2.5)
assertTrue(cancelled.accepted == true, "outgoing can cancel")
assertEqual(cancelled.reason, "transfer_cancelled", "cancel reason")

resetState()
captureApi.RequestCapture(3101, 3102, 1.0)
local missingCapture = transferApi.RequestCustodyTransfer(3105, 3102, 3101, 2.0)
assertFalse(missingCapture.accepted == true, "non-custodian cannot request")
assertEqual(missingCapture.reason, "custodian_mismatch", "non-custodian reason")

resetState()
captureApi.RequestCapture(3101, 3102, 1.0)
captureApi.PromoteTargetToContained(3102, 2.0)
local containedRequest = transferApi.RequestCustodyTransfer(3101, 3102, 3105, 3.0)
assertTrue(containedRequest.accepted == true, "contained transfer request accepted")
local containedConfirm = transferApi.ConfirmCustodyTransfer(3105, containedRequest.request.requestId, 4.0)
assertTrue(containedConfirm.accepted == true, "contained transfer confirm accepted")
assertEqual(containedConfirm.record.containmentPhase, "contained", "contained phase preserved")

print("custody_transfer_service_runtime_entrypoint: all checks passed")
