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

local function makeNode(name: string, className: string?)
	local node: any = {
		Name = name,
		ClassName = className or "Folder",
		_Children = {},
	}

	function node:WaitForChild(childName: string): any
		return self._Children[childName]
	end

	return node
end

local configFolder = makeNode("Config")
configFolder._Children["SocialEconomyConfig"] = "../../ReplicatedStorage/Shared/Config/SocialEconomyConfig"
configFolder._Children["TrophyConfig"] = "../../ReplicatedStorage/Shared/Config/TrophyConfig"

local giantRealmFolder = makeNode("GiantRealm")
giantRealmFolder._Children["SocialEconomyState"] = "../../ReplicatedStorage/Shared/GiantRealm/SocialEconomyState"

local sharedFolder = makeNode("Shared")
sharedFolder._Children["Config"] = configFolder
sharedFolder._Children["GiantRealm"] = giantRealmFolder

local replicatedStorage = makeNode("ReplicatedStorage")
replicatedStorage._Children["Shared"] = sharedFolder

local ownerPlayer = {
	UserId = 5001,
	_Attributes = {},
	SetAttribute = function(self: any, attributeName: string, value: any)
		self._Attributes[attributeName] = value
	end,
	GetAttribute = function(self: any, attributeName: string): any
		return self._Attributes[attributeName]
	end,
}

local playersList = { ownerPlayer }

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
		}
	end
	return nil
end

game = fakeGame

_G._GiantBuildModeService_QueryAPI = {
	GetActiveGiantRealmOwnerUserId = function(): number
		return 5001
	end,
}

local SocialEconomyConfig = require("../src/ReplicatedStorage/Shared/Config/SocialEconomyConfig")
local TrophyConfig = require("../src/ReplicatedStorage/Shared/Config/TrophyConfig")

require("../src/ServerScriptService/Services/SocialEconomyService.server")

local socialApi = _G._SocialEconomyService_QueryAPI
assertTrue(type(socialApi) == "table", "social economy query api present")

socialApi.ResetForTests()

local captureResult =
	socialApi.RecordTrophySocialEvent(TrophyConfig.Kinds.CaptureSuccess, "trophy-capture-5001-5101-12500", 12.5)
assertTrue(captureResult.accepted, "capture social event recorded")
assertEqual(socialApi.GetControl(), 55, "capture increments control")
assertEqual(ownerPlayer:GetAttribute(SocialEconomyConfig.StateAttributes.Control), 55, "realm owner control attribute")
assertEqual(ownerPlayer:GetAttribute(SocialEconomyConfig.StateAttributes.Favor), 50, "realm owner favor unchanged")

local releaseResult =
	socialApi.RecordTrophySocialEvent(TrophyConfig.Kinds.NegotiatedRelease, "containment-released-5001-5101-20000", 20)
assertTrue(releaseResult.accepted, "negotiated release social event recorded")
assertEqual(socialApi.GetFavor(), 55, "negotiated release increments favor")

local effectSnapshot = socialApi.GetEffectSnapshot()
assertTrue(type(effectSnapshot.favorComplianceBonus) == "number", "effect snapshot favor bonus")
assertTrue(type(effectSnapshot.controlIntimidationBonus) == "number", "effect snapshot control bonus")
assertEqual(
	ownerPlayer:GetAttribute(SocialEconomyConfig.StateAttributes.DominantAxis),
	effectSnapshot.dominantAxis,
	"realm owner dominant axis attribute"
)

local snapshot = socialApi.GetSnapshot()
assertEqual(#snapshot.recentEvents, 2, "snapshot includes recent events")
assertEqual(snapshot.recentEvents[2].eventKind, TrophyConfig.Kinds.NegotiatedRelease, "release event kind")

print("social_economy_service_runtime_entrypoint.spec.luau: all checks passed")
