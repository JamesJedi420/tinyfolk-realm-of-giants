--!nocheck
--!nolint BuiltinGlobalWrite
-- selene: allow(global_usage)
local globalEnv: any = getfenv()

local function assertTrue(condition: boolean, label: string)
	if not condition then
		error(string.format("FAIL [%s]: expected true, got false", label))
	end
	print(string.format("PASS [%s]", label))
end

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(string.format("FAIL [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual)))
	end
	print(string.format("PASS [%s]", label))
end

local function makeNode(name: string, className: string?)
	local node: any = {
		Name = name,
		ClassName = className or "Folder",
		_Children = {},
		Parent = nil,
	}

	function node:IsA(expectedClass: string): boolean
		return self.ClassName == expectedClass
	end

	function node:FindFirstChild(childName: string): any
		return self._Children[childName]
	end

	function node:WaitForChild(childName: string, _timeout: number?): any
		return self._Children[childName]
	end

	return node
end

local function addChild(parent: any, childName: string, child: any)
	parent._Children[childName] = child
	child.Parent = parent
end

local function makeRemoteEvent(remoteName: string)
	local remote: any = {
		Name = remoteName,
		ClassName = "RemoteEvent",
		Parent = nil,
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

	function remote:FireClient(_player: any, payload: any)
		if self._Handler ~= nil then
			self._Handler(payload)
		end
	end

	return remote
end

Instance = {
	new = function(className: string): any
		if className == "Folder" then
			return makeNode("Folder", "Folder")
		end
		if className == "RemoteEvent" then
			return makeRemoteEvent("GeneratedRemote")
		end
		error(string.format("unsupported Instance.new(%q)", className))
	end,
} :: any

local configFolder = makeNode("Config")
configFolder._Children["RoleConfig"] = "../../ReplicatedStorage/Shared/Config/RoleConfig"
configFolder._Children["VillageWorksiteUpgradeConfig"] =
	"../../ReplicatedStorage/Shared/Config/VillageWorksiteUpgradeConfig"

local giantRealmFolder = makeNode("GiantRealm")
giantRealmFolder._Children["VillageWorksiteUpgradeState"] =
	"../../ReplicatedStorage/Shared/GiantRealm/VillageWorksiteUpgradeState"

local sharedFolder = makeNode("Shared")
addChild(sharedFolder, "Config", configFolder)
addChild(sharedFolder, "GiantRealm", giantRealmFolder)

local remotesFolder = makeNode("Remotes")
addChild(remotesFolder, "VillageWorksiteUpgradeRequest", makeRemoteEvent("VillageWorksiteUpgradeRequest"))
addChild(remotesFolder, "VillageWorksiteUpgradeResponse", makeRemoteEvent("VillageWorksiteUpgradeResponse"))
local replicatedStorage = makeNode("ReplicatedStorage")
addChild(replicatedStorage, "Shared", sharedFolder)
addChild(replicatedStorage, "Remotes", remotesFolder)

local fakeGame: any = {}
function fakeGame:GetService(serviceName: string): any
	if serviceName == "ReplicatedStorage" then
		return replicatedStorage
	end
	return nil
end

game = fakeGame

local spendCalls: { any } = {}
_G._GiantBuildModeService_QueryAPI = {
	GetRealmOwnerUserId = function()
		return 9402
	end,
	SpendWorksiteUpgradeCost = function(spend: any): any
		table.insert(spendCalls, spend)
		return { accepted = true, spentFrom = "session" }
	end,
	RollbackWorksiteUpgradeSpend = function() end,
}

require("../src/ServerScriptService/Services/VillageWorksiteUpgradeService.server")

local upgradeApi = globalEnv._VillageWorksiteUpgradeService_QueryAPI
assertTrue(type(upgradeApi) == "table", "village upgrade query api available")

local giantPlayer: any = {
	UserId = 9402,
	GetAttribute = function(_self: any, attributeName: string): any
		if attributeName == "Role" then
			return "Giant"
		end
		return nil
	end,
}

local responseRemote = remotesFolder:WaitForChild("VillageWorksiteUpgradeResponse")
local responses: { any } = {}
responseRemote._Handler = function(payload: any)
	table.insert(responses, payload)
end

local result = upgradeApi.RequestUpgradeForTests(giantPlayer, "WorkStation_A", 100, responseRemote)
assertTrue(result.accepted == true, "giant owner upgrade accepted")
assertEqual(result.level, 1, "first upgrade level")
assertEqual(#spendCalls, 1, "upgrade routes spend through build mode api")
assertEqual(spendCalls[1].wood, 10, "workstation level 1 wood cost")
assertEqual(responses[#responses].accepted, true, "upgrade response accepted")

print("village_worksite_upgrade_service_runtime_entrypoint: all checks passed")
