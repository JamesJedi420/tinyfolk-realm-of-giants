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
addChild(remotesFolder, "RansomBoardPost", makeRemoteEvent("RansomBoardPost"))
addChild(remotesFolder, "RansomBoardSettle", makeRemoteEvent("RansomBoardSettle"))
addChild(remotesFolder, "RansomBoardCancel", makeRemoteEvent("RansomBoardCancel"))
addChild(remotesFolder, "RansomBoardNotify", makeRemoteEvent("RansomBoardNotify"))

local configFolder = makeNode("Config", "Folder")
addChild(configFolder, "CaptureConfig", "../../ReplicatedStorage/Shared/Config/CaptureConfig")
addChild(configFolder, "RansomBoardConfig", "../../ReplicatedStorage/Shared/Config/RansomBoardConfig")
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
addChild(giantRealmFolder, "RansomBoardState", "../../ReplicatedStorage/Shared/GiantRealm/RansomBoardState")
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

local workspaceService = makeNode("Workspace")
local mapFolder = makeNode("Map")
local stationsFolder = makeNode("Stations")
addChild(mapFolder, "Stations", stationsFolder)
addChild(workspaceService, "Map", mapFolder)

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
		return workspaceService
	end
	error("unsupported service " .. serviceName)
	return nil
end

game = fakeGame

local ResourceFlowState = require("../src/ServerScriptService/Services/ResourceFlowState")

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
	RecordEventFromPayload = function(payload: any): any
		table.insert(eventLogCalls, payload)
		return { accepted = true }
	end,
}
_G._RealmObjectiveService_QueryAPI = {
	IsEscapeObjectiveThresholdMet = function(): boolean
		return false
	end,
}

require("../src/ServerScriptService/Services/CaptureService.server")
require("../src/ServerScriptService/Services/RansomBoardService.server")

ResourceFlowState.ResetSession("ransom_board_service_runtime_entrypoint")

local captureApi: any = _G._CaptureService_QueryAPI
local ransomApi: any = _G._RansomBoardService_QueryAPI
assertTrue(type(captureApi) == "table", "capture api exposed")
assertTrue(type(ransomApi) == "table", "ransom board api exposed")

local giant = MockPlayer.new(5101, "Giant", {
	role = "Giant",
	positionZ = 0,
	health = 100,
})
local ally = MockPlayer.new(5103, "Ally", {
	role = "Tinyfolk",
	positionZ = 0,
	health = 100,
})
local target = MockPlayer.new(5102, "Target", {
	role = "Tinyfolk",
	positionZ = 0,
	health = 100,
})

playersList = { giant, ally, target }

local function setDowned(player: any, value: boolean)
	player:SetAttribute("DownedIsDowned", value)
end

local function resetState()
	captureApi.ResetForTests()
	ransomApi.ResetForTests()
	ResourceFlowState.ResetSession("ransom_board_service_runtime_entrypoint")
	eventLogCalls = {}
	giant:SetAttribute("RansomBoardActiveOfferId", nil)
	target:SetAttribute("RansomBoardActiveOfferId", nil)
	setDowned(target, true)
end

resetState()

local captured = captureApi.RequestCapture(giant.UserId, target.UserId, 10)
assertTrue(captured.accepted == true, "capture accepted for ransom flow")

local posted = ransomApi.PostRansomOffer(giant.UserId, target.UserId, "payment_food", 5, 10.5)
assertTrue(posted.accepted == true, "ransom post accepted")
assertTrue(type(posted.offer) == "table", "ransom post returns offer")
assertEqual(posted.offer.terms.foodCost, 5, "posted food cost")

local boardEntries = ransomApi.GetBoardEntries(10.5)
assertTrue(#boardEntries >= 1, "board lists active offer")
assertEqual(target:GetAttribute("RansomBoardTermsFoodCost"), 5, "target receives terms food cost attribute")

ResourceFlowState.AddStoredAtomic(0, 0, "ransom_test_seed", 5)
local settled = ransomApi.SettleRansomOffer(ally.UserId, posted.offer.offerId, 11)
assertTrue(settled.accepted == true, "ally payment settle accepted")
assertEqual(ResourceFlowState.GetMaterialSnapshot("Food").stored, 0, "food spent on ransom settle")
assertTrue(captureApi.GetTargetCapture(target.UserId, 11) == nil, "target released after ransom settle")
assertTrue(#eventLogCalls >= 2, "post and settle logged")

resetState()
captured = captureApi.RequestCapture(giant.UserId, target.UserId, 20)
assertTrue(captured.accepted == true, "second capture accepted")
posted = ransomApi.PostRansomOffer(giant.UserId, target.UserId, "objective_escape_ready", 0, 20.5)
assertTrue(posted.accepted == true, "objective ransom post accepted")

_G._RealmObjectiveService_QueryAPI.IsEscapeObjectiveThresholdMet = function(): boolean
	return true
end
settled = ransomApi.SettleRansomOffer(ally.UserId, posted.offer.offerId, 21)
assertTrue(settled.accepted == true, "objective ransom settle accepted")
assertTrue(captureApi.GetTargetCapture(target.UserId, 21) == nil, "target released after objective settle")

print("ransom_board_service_runtime_entrypoint: all checks passed")
