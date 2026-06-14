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

local configFolder = makeNode("Config", "Folder")
addChild(configFolder, "CaptureConfig", "../../ReplicatedStorage/Shared/Config/CaptureConfig")
addChild(
	configFolder,
	"RepeatedTargetingAbuseConfig",
	"../../ReplicatedStorage/Shared/Config/RepeatedTargetingAbuseConfig"
)

local giantRealmFolder = makeNode("GiantRealm", "Folder")
addChild(
	giantRealmFolder,
	"RepeatedTargetingAbuseState",
	"../../ReplicatedStorage/Shared/GiantRealm/RepeatedTargetingAbuseState"
)

local sharedFolder = makeNode("Shared", "Folder")
addChild(sharedFolder, "Config", configFolder)
addChild(sharedFolder, "GiantRealm", giantRealmFolder)

local replicatedStorage = makeNode("ReplicatedStorage", "ReplicatedStorage")
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
	error("unsupported service " .. serviceName)
	return nil
end

game = fakeGame

local eventLogCalls: { any } = {}
_G._RuntimeEventLogService_QueryAPI = {
	RecordEventFromPayload = function(payload: any): any
		table.insert(eventLogCalls, payload)
		return { accepted = true }
	end,
}

require("../src/ServerScriptService/Services/RepeatedTargetingAbuseService.server")

local abuseApi: any = _G._RepeatedTargetingAbuseService_QueryAPI
assertTrue(type(abuseApi) == "table", "abuse service api exposed")

local giant = MockPlayer.new(4101, "Giant", {
	role = "Giant",
	positionZ = 0,
	health = 100,
})
local target = MockPlayer.new(4102, "Target", {
	role = "Tinyfolk",
	positionZ = 0,
	health = 100,
})
playersList = { giant, target }

local function resetState()
	abuseApi.ResetForTests()
	eventLogCalls = {}
	giant:SetAttribute("RepeatedTargetingAbuseFlag", nil)
	target:SetAttribute("RepeatedTargetingAbuseFlag", nil)
end

resetState()

for index = 1, 3 do
	local result = abuseApi.RecordCaptureStart(giant.UserId, target.UserId, index)
	assertTrue(result.accepted, "capture start records accepted")
end

local snapshot = abuseApi.GetPairSnapshot(giant.UserId, target.UserId, 3)
assertTrue(snapshot.captureCount >= 3, "pair snapshot reflects repeated captures")

local loops = abuseApi.GetRecentSuspiciousLoops(5)
assertTrue(#loops >= 1, "service retains suspicious loop records")
assertEqual(loops[1].patternKind, "pair_repeat_targeting", "service records pair repeat pattern")

assertTrue(#eventLogCalls >= 1, "service logs suspicious loop to runtime event log")
assertEqual(eventLogCalls[1].category, "repeated_targeting_abuse", "event log category")

assertTrue(giant:GetAttribute("RepeatedTargetingAbuseFlag") == true, "giant receives abuse flag attribute")
assertTrue(target:GetAttribute("RepeatedTargetingAbuseFlag") == true, "target receives abuse flag attribute")

resetState()
abuseApi.RecordCustodyEnd(giant.UserId, target.UserId, "released", 1)
abuseApi.RecordCustodyEnd(giant.UserId, target.UserId, "released", 2)
abuseApi.RecordCustodyEnd(giant.UserId, target.UserId, "released", 3)
abuseApi.RecordCustodyEnd(giant.UserId, target.UserId, "released", 4)
abuseApi.RecordCustodyEnd(giant.UserId, target.UserId, "released", 5)
local targetSnapshot = abuseApi.GetTargetSnapshot(target.UserId, 5)
assertTrue(targetSnapshot.eventCount >= 5, "target snapshot reflects custody events")

print("repeated_targeting_abuse_service_runtime_entrypoint: all checks passed")
