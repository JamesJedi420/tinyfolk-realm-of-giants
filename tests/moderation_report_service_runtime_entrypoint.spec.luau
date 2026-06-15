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
addChild(remotesFolder, "ModerationReportRequestExport", makeRemoteEvent("ModerationReportRequestExport"))

local configFolder = makeNode("Config", "Folder")
addChild(configFolder, "CaptureConfig", "../../ReplicatedStorage/Shared/Config/CaptureConfig")
addChild(configFolder, "CustodyTransferConfig", "../../ReplicatedStorage/Shared/Config/CustodyTransferConfig")
addChild(configFolder, "ModerationReportConfig", "../../ReplicatedStorage/Shared/Config/ModerationReportConfig")
addChild(configFolder, "RansomBoardConfig", "../../ReplicatedStorage/Shared/Config/RansomBoardConfig")
addChild(
	configFolder,
	"RepeatedTargetingAbuseConfig",
	"../../ReplicatedStorage/Shared/Config/RepeatedTargetingAbuseConfig"
)
addChild(configFolder, "RescueContractConfig", "../../ReplicatedStorage/Shared/Config/RescueContractConfig")

local giantRealmFolder = makeNode("GiantRealm", "Folder")
addChild(giantRealmFolder, "ModerationReportState", "../../ReplicatedStorage/Shared/GiantRealm/ModerationReportState")

local sharedFolder = makeNode("Shared", "Folder")
addChild(sharedFolder, "Config", configFolder)
addChild(sharedFolder, "GiantRealm", giantRealmFolder)

local replicatedStorage = makeNode("ReplicatedStorage", "ReplicatedStorage")
addChild(replicatedStorage, "Shared", sharedFolder)
addChild(replicatedStorage, "Remotes", remotesFolder)

local eventLogCalls: { any } = {}
local playersList: { any } = {}

local fakeGame: any = {
	JobId = "session_test",
}
function fakeGame:GetService(serviceName: string): any
	if serviceName == "ReplicatedStorage" then
		return replicatedStorage
	end
	if serviceName == "Players" then
		return {
			GetPlayers = function()
				return playersList
			end,
			PlayerAdded = makeSignal(),
			PlayerRemoving = makeSignal(),
		}
	end
	if serviceName == "RunService" then
		return {
			Heartbeat = {
				Connect = function(_self: any, _callback: () -> ()) end,
			},
		}
	end
	error(string.format("unsupported service: %s", serviceName))
	return nil
end

game = fakeGame

local activeCapture = {
	custodianUserId = 5101,
	targetUserId = 5102,
	startedAt = 10,
	expiresAt = 30,
	containmentPhase = "contained",
}

local activeRansomOffer = {
	offerId = "offer_1",
	targetUserId = 5102,
	terms = {
		custodianUserId = 5101,
		targetUserId = 5102,
		settlementKind = "payment_food",
		foodCost = 5,
	},
}

_G._EventLogService_QueryAPI = {
	RecordEventFromPayload = function(payload: any): any
		table.insert(eventLogCalls, payload)
		return { accepted = true }
	end,
	GetRecentEvents = function(_limit: number?): any
		return {
			{
				sequence = 1,
				timestamp = 10,
				category = "capture",
				message = "capture accepted",
				severity = "info",
				metadata = { targetUserId = 5102, custodianUserId = 5101 },
			},
			{
				sequence = 2,
				timestamp = 11,
				category = "ransom_board",
				message = "ransom posted",
				severity = "info",
				metadata = { offerId = "offer_1", token = "secret" },
			},
		}
	end,
	ResetForTests = function()
		eventLogCalls = {}
	end,
}

_G._CaptureService_QueryAPI = {
	GetTargetCapture = function(targetUserId: number): any
		if targetUserId == activeCapture.targetUserId then
			return activeCapture
		end
		return nil
	end,
	ResetForTests = function() end,
}

_G._RansomBoardService_QueryAPI = {
	GetActiveOfferForTarget = function(targetUserId: number): any
		if targetUserId == activeRansomOffer.targetUserId then
			return activeRansomOffer
		end
		return nil
	end,
	GetBoardEntries = function(): any
		return { activeRansomOffer }
	end,
	ResetForTests = function() end,
}

_G._CustodyTransferService_QueryAPI = {
	GetPendingTransferForTarget = function(): any
		return nil
	end,
	ResetForTests = function() end,
}

_G._RepeatedTargetingAbuseService_QueryAPI = {
	GetTargetSnapshot = function(targetUserId: number): any
		return {
			targetUserId = targetUserId,
			recentCaptureCount = 2,
		}
	end,
	GetRecentSuspiciousLoops = function(): any
		return {
			{
				targetUserId = 5102,
				patternKind = "pair_repeat_targeting",
				eventCount = 3,
			},
		}
	end,
	ResetForTests = function() end,
}

require("../src/ServerScriptService/Services/ModerationReportService.server")

local reportApi: any = _G._ModerationReportService_QueryAPI
assertTrue(type(reportApi) == "table", "moderation report api exposed")

local target = MockPlayer.new(5102, "Target", {
	role = "Tinyfolk",
	positionZ = 0,
	health = 100,
})
target:SetAttribute("GiantRealmId", "giant_realm_9001")
target:SetAttribute("CaptureActive", true)

playersList = { target }

reportApi.ResetForTests()
reportApi.RefreshAffordanceForPlayer(target.UserId)
local affordance = reportApi.GetAffordanceSurfaces(target.UserId, 10)
assertTrue(affordance.available == true, "capture affordance available")
assertEqual(target:GetAttribute("ModerationReportAffordanceAvailable"), true, "affordance attribute projected")

local built = reportApi.BuildReportContext(target.UserId, "capture", 10.5)
assertTrue(built.accepted == true, "build report context accepted")
assertEqual(built.summary.realmId, "giant_realm_9001", "summary realm id")
assertEqual(built.summary.sessionId, "session_test", "summary session id")
assertEqual(built.summary.capturingUserId, 5101, "summary capturing user id")
assertEqual(built.summary.capturedUserId, 5102, "summary captured user id")
assertTrue(type(built.summary.recentEvents) == "table", "summary includes recent events")
assertEqual(built.summary.recentEvents[2].metadata.token, nil, "summary strips blocked metadata")

local exported = reportApi.ExportReportSummary(target.UserId, "capture", 11)
assertTrue(exported.accepted == true, "export report summary accepted")
assertEqual(exported.summary.surfaceKind, "capture", "export surface kind")
assertTrue(#eventLogCalls >= 1, "export logs moderation report event")
assertEqual(
	target:GetAttribute("ModerationReportLastExportReportId"),
	exported.summary.reportId,
	"export report id attribute"
)

reportApi.RefreshAffordanceForPlayer(target.UserId)
local ransomAffordance = reportApi.GetAffordanceSurfaces(target.UserId, 20.5)
local hasRansomSurface = false
for _, surfaceKind in ipairs(ransomAffordance.surfaces) do
	if surfaceKind == "ransom" then
		hasRansomSurface = true
	end
end
assertTrue(hasRansomSurface, "ransom affordance surface available")

local ransomExport = reportApi.ExportReportSummary(target.UserId, "ransom", 21)
assertTrue(ransomExport.accepted == true, "ransom export accepted")
assertEqual(ransomExport.summary.surfaceKind, "ransom", "ransom export surface kind")
assertTrue(type(ransomExport.summary.surfaceDetails) == "table", "ransom export includes surface details")

target:SetAttribute("RepeatedTargetingAbuseFlag", true)
reportApi.RefreshAffordanceForPlayer(target.UserId)
local abuseExport = reportApi.ExportReportSummary(target.UserId, "repeated_blocking", 22)
assertTrue(abuseExport.accepted == true, "repeated blocking export accepted")
assertTrue(type(abuseExport.summary.abuseSignals) == "table", "abuse signals included")

target:SetAttribute("RescueContractLastReason", "escape_action_blocked")
reportApi.RefreshAffordanceForPlayer(target.UserId)
local rescueExport = reportApi.ExportReportSummary(target.UserId, "rescue_blocking", 23)
assertTrue(rescueExport.accepted == true, "rescue blocking export accepted")

print("moderation_report_service_runtime_entrypoint: all checks passed")
