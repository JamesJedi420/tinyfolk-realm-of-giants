--!nocheck
--!nolint BuiltinGlobalWrite
-- selene: allow(global_usage)

local ProfilePersistenceGateway = require("../src/ServerScriptService/Services/ProfilePersistenceGateway")

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(string.format("FAIL [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual)))
	end
	print(string.format("PASS [%s]", label))
end

local function assertTrue(condition: boolean, label: string)
	assertEqual(condition, true, label)
end

local function makeNode(name: string, className: string?)
	local node: any = {
		Name = name,
		ClassName = className or "Folder",
		_Children = {},
	}

	function node.IsA(self: any, expectedClass: string): boolean
		return self.ClassName == expectedClass
	end

	function node.FindFirstChild(self: any, childName: string): any
		return self._Children[childName]
	end

	function node:WaitForChild(childName: string): any
		return self._Children[childName]
	end

	return node
end

local function cloneTable(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local result = {}
	for key, child in pairs(value) do
		result[key] = cloneTable(child)
	end
	return result
end

local function makeSignal()
	return {
		Connect = function(_self: any, callback: (...any) -> ())
			callback()
			return {}
		end,
	}
end

local profileDataByUserId: { [number]: any } = {}
local ownerLayer = {
	LoadPlayerProfile = function(_profileKey: string, userId: number): any
		local data = profileDataByUserId[userId]
		if type(data) ~= "table" then
			data = ProfilePersistenceGateway.LoadDefaultPlayerProfile(userId).data
			profileDataByUserId[userId] = cloneTable(data)
		end
		return { ok = true, operation = "LoadPlayerProfile", data = cloneTable(profileDataByUserId[userId]) }
	end,
	SavePlayerProfile = function(_profileKey: string, userId: number, data: any): any
		profileDataByUserId[userId] = cloneTable(data)
		return { ok = true, operation = "SavePlayerProfile" }
	end,
	ReleasePlayerProfile = function(): any
		return { ok = true, operation = "ReleasePlayerProfile" }
	end,
	LoadGiantRealmProfile = function(): any
		return { ok = true, operation = "LoadGiantRealmProfile", data = {} }
	end,
	SaveGiantRealmProfile = function(): any
		return { ok = true, operation = "SaveGiantRealmProfile" }
	end,
	ReleaseGiantRealmProfile = function(): any
		return { ok = true, operation = "ReleaseGiantRealmProfile" }
	end,
}

ProfilePersistenceGateway.ResetForTests()
ProfilePersistenceGateway.ConfigureOwnerLayer(ownerLayer)

local configFolder = makeNode("Config")
configFolder._Children["RoleConfig"] = "../../ReplicatedStorage/Shared/Config/RoleConfig"
configFolder._Children["TrophyConfig"] = "../../ReplicatedStorage/Shared/Config/TrophyConfig"
configFolder._Children["GiantReputationConfig"] = "../../ReplicatedStorage/Shared/Config/GiantReputationConfig"
configFolder._Children["SocialEconomyConfig"] = "../../ReplicatedStorage/Shared/Config/SocialEconomyConfig"

local giantRealmFolder = makeNode("GiantRealm")
giantRealmFolder._Children["TrophyState"] = "../../ReplicatedStorage/Shared/GiantRealm/TrophyState"
giantRealmFolder._Children["GiantReputationState"] = "../../ReplicatedStorage/Shared/GiantRealm/GiantReputationState"
giantRealmFolder._Children["SocialEconomyState"] = "../../ReplicatedStorage/Shared/GiantRealm/SocialEconomyState"
giantRealmFolder._Children["TrophyCasePresentation"] =
	"../../ReplicatedStorage/Shared/GiantRealm/TrophyCasePresentation"
giantRealmFolder._Children["TrophyDisplayPolicyProfileState"] =
	"../../ReplicatedStorage/Shared/GiantRealm/TrophyDisplayPolicyProfileState"

local sharedFolder = makeNode("Shared")
sharedFolder._Children["Config"] = configFolder
sharedFolder._Children["GiantRealm"] = giantRealmFolder

local function makeRemoteEvent(remoteName: string)
	local remote: any = {
		Name = remoteName,
		ClassName = "RemoteEvent",
	}

	function remote.IsA(self: any, expectedClass: string): boolean
		return self.ClassName == expectedClass
	end

	remote.OnServerEvent = {
		Connect = function() end,
	}

	return remote
end

local remotesFolder = makeNode("Remotes")
remotesFolder._Children["TrophyDisplayPolicyUpdateRequest"] = makeRemoteEvent("TrophyDisplayPolicyUpdateRequest")
remotesFolder._Children["TrophyDisplayPolicyUpdateResponse"] = makeRemoteEvent("TrophyDisplayPolicyUpdateResponse")

local replicatedStorage = makeNode("ReplicatedStorage")
replicatedStorage._Children["Shared"] = sharedFolder
replicatedStorage._Children["Remotes"] = remotesFolder

local function makePlayer(userId: number, role: string?): any
	return {
		UserId = userId,
		_Attributes = if role ~= nil then { Role = role } else {},
		_RoleChangedSignal = makeSignal(),
		SetAttribute = function(self: any, attributeName: string, value: any)
			self._Attributes[attributeName] = value
		end,
		GetAttribute = function(self: any, attributeName: string): any
			return self._Attributes[attributeName]
		end,
		GetAttributeChangedSignal = function(self: any, attributeName: string): any
			if attributeName == "Role" then
				return self._RoleChangedSignal
			end
			return makeSignal()
		end,
	}
end

local ownerPlayer = makePlayer(5001, "Giant")
local targetPlayer = makePlayer(5101, "Tinyfolk")
local playersList = { ownerPlayer, targetPlayer }
local playerAddedSignal = {
	Connect = function(_self: any, _callback: (...any) -> ())
		return {}
	end,
}

assertTrue(ProfilePersistenceGateway.LoadPlayerProfile(targetPlayer).ok, "target profile loaded")

local trophyCasePart = {
	Name = "GiantDwelling_TrophyCasePlaque",
	ClassName = "Part",
	_Attributes = {
		TrophyCaseSurface = true,
	},
	IsA = function(_self: any, className: string): boolean
		return className == "BasePart"
	end,
	GetAttribute = function(self: any, attributeName: string): any
		return self._Attributes[attributeName]
	end,
	SetAttribute = function(self: any, attributeName: string, value: any)
		self._Attributes[attributeName] = value
	end,
}

local workspaceService = {
	GetDescendants = function(): { any }
		return { trophyCasePart }
	end,
}

local fakeGame: any = {}
function fakeGame:GetService(serviceName: string): any
	if serviceName == "ReplicatedStorage" then
		return replicatedStorage
	end
	if serviceName == "Players" then
		return {
			GetPlayers = function()
				return playersList
			end,
			PlayerAdded = playerAddedSignal,
		}
	end
	if serviceName == "Workspace" then
		return workspaceService
	end
	return nil
end

game = fakeGame

_G._GiantBuildModeService_QueryAPI = {
	GetActiveGiantRealmOwnerUserId = function(): number
		return 5001
	end,
}

local TrophyConfig = require("../src/ReplicatedStorage/Shared/Config/TrophyConfig")
local GiantReputationConfig = require("../src/ReplicatedStorage/Shared/Config/GiantReputationConfig")
local SocialEconomyConfig = require("../src/ReplicatedStorage/Shared/Config/SocialEconomyConfig")

require("../src/ServerScriptService/Services/GiantReputationService.server")
require("../src/ServerScriptService/Services/TrophyDisplayPolicyService.server")
require("../src/ServerScriptService/Services/SocialEconomyService.server")
require("../src/ServerScriptService/Services/TrophyService.server")

local trophyApi = _G._TrophyService_QueryAPI
assertTrue(type(trophyApi) == "table", "trophy query api present")

trophyApi.ResetForTests()

local captureResult = trophyApi.RecordCaptureSuccess(5001, 5101, 12.5)
assertTrue(captureResult.accepted, "capture trophy recorded")
assertEqual(trophyApi.GetTrophyCount(), 1, "capture increments trophy count")
assertEqual(ownerPlayer:GetAttribute(TrophyConfig.StateAttributes.Count), 1, "realm owner trophy count attribute")
assertTrue(
	string.find(ownerPlayer:GetAttribute(TrophyConfig.StateAttributes.LatestSummary), "Capture Secured") ~= nil,
	"latest summary includes capture title"
)

local containmentResult = trophyApi.RecordContainmentEnd({
	operationId = "containment-released-5001-5101-1000",
	custodianUserId = 5001,
	targetUserId = 5101,
	endedAt = 20,
	endReason = "released",
	heldSeconds = 4,
})
assertTrue(containmentResult.accepted, "containment trophy recorded")
assertEqual(
	containmentResult.record.trophyKind,
	TrophyConfig.Kinds.NegotiatedRelease,
	"released maps to negotiated release"
)
assertEqual(trophyApi.GetTrophyCount(), 2, "containment increments trophy count")

local escapeResult = trophyApi.RecordContainmentEnd({
	operationId = "containment-escaped-5001-5101-3000",
	custodianUserId = 5001,
	targetUserId = 5101,
	endedAt = 30,
	endReason = "escaped",
	heldSeconds = 8,
})
assertTrue(escapeResult.accepted, "escape failure trophy recorded")
assertEqual(escapeResult.record.trophyKind, TrophyConfig.Kinds.ContainmentEscapeFailure, "escape failure trophy kind")
assertEqual(trophyApi.GetTrophyCount(), 3, "escape failure increments trophy count")

local raidDefenseResult = trophyApi.RecordRaidDefenseWin(5001, 5201, "snare-trap-runtime-a", 35)
assertTrue(raidDefenseResult.accepted, "raid defense trophy recorded")
assertEqual(raidDefenseResult.record.trophyKind, TrophyConfig.Kinds.RaidDefenseWin, "raid defense trophy kind")
assertEqual(trophyApi.GetTrophyCount(), 4, "raid defense increments trophy count")

local reputationApi = _G._GiantReputationService_QueryAPI
assertEqual(reputationApi.GetScore(), 72, "trophies grant reputation score")
assertEqual(ownerPlayer:GetAttribute(GiantReputationConfig.StateAttributes.Score), 72, "reputation score attribute")

local socialApi = _G._SocialEconomyService_QueryAPI
assertEqual(socialApi.GetFavor(), 55, "trophies grant favor from negotiated release")
assertEqual(socialApi.GetControl(), 58, "trophies grant control from capture and escape failure")
assertEqual(ownerPlayer:GetAttribute(SocialEconomyConfig.StateAttributes.Favor), 55, "social favor attribute")
assertEqual(ownerPlayer:GetAttribute(SocialEconomyConfig.StateAttributes.Control), 58, "social control attribute")
assertEqual(
	ownerPlayer:GetAttribute(SocialEconomyConfig.StateAttributes.LastEventKind),
	TrophyConfig.Kinds.ContainmentEscapeFailure,
	"last mapped social event kind remains escape failure"
)

local caseModel = trophyApi.GetCaseModel()
assertEqual(caseModel.count, 4, "case model count")
assertTrue(string.find(caseModel.body, "Intruder Snared") ~= nil, "case model lists newest trophy")
assertEqual(
	ownerPlayer:GetAttribute(TrophyConfig.StateAttributes.CaseSummary),
	caseModel.body,
	"realm owner case summary attribute"
)
assertTrue(
	type(ownerPlayer:GetAttribute(TrophyConfig.StateAttributes.CaseUpdatedAt)) == "number",
	"realm owner case updated at attribute"
)
assertEqual(
	trophyCasePart:GetAttribute(TrophyConfig.MapSurfaceAttributes.Summary),
	caseModel.body,
	"map surface case summary attribute"
)
assertEqual(trophyCasePart:GetAttribute(TrophyConfig.MapSurfaceAttributes.Count), 4, "map surface case count attribute")

local persistence = trophyApi.BuildPersistenceState()
assertEqual(#persistence.trophies, 4, "persistence includes trophies")
assertTrue(
	persistence.trophies[1].targetDisplayToken:find("^ref%-") ~= nil,
	"persisted trophy uses display token not raw target id"
)
assertEqual(persistence.trophies[1].targetUserId, nil, "persisted trophy omits raw target user id")

trophyApi.ResetForTests()
local applied, applyReason = trophyApi.ApplyPersistenceState(persistence)
assertTrue(applied, "apply persistence accepted")
assertEqual(applyReason, nil, "apply persistence reason")
assertEqual(trophyApi.GetTrophyCount(), 4, "apply persistence restores trophies")

trophyApi.ResetForTests()
local policyApi = _G._TrophyDisplayPolicyService_QueryAPI
policyApi.SetOptOutForPlayer(targetPlayer, true)
local optedOutCapture = trophyApi.RecordCaptureSuccess(5001, 5101, 99)
assertTrue(optedOutCapture.accepted, "opt-out capture trophy recorded")
assertEqual(
	optedOutCapture.record.targetDisplayToken,
	TrophyConfig.AnonymousTargetDisplayToken,
	"opt-out capture uses anonymous display token"
)

print("trophy_service_runtime_entrypoint.spec.luau: all checks passed")
