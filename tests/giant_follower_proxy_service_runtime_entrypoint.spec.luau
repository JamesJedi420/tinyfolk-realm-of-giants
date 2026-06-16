--!nocheck
--!nolint BuiltinGlobalWrite
-- selene: allow(global_usage)

local MockPlayer = require("../tests/mocks/MockPlayer")
local globalEnv: any = getfenv()

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
	if type(child) == "table" then
		child.Parent = parent
	end
end

local configFolder = makeNode("Config")
addChild(configFolder, "RoleConfig", "../../ReplicatedStorage/Shared/Config/RoleConfig")
addChild(configFolder, "GiantFollowerProxyConfig", "../../ReplicatedStorage/Shared/Config/GiantFollowerProxyConfig")

local giantRealmFolder = makeNode("GiantRealm")
addChild(
	giantRealmFolder,
	"GiantFollowerProxyState",
	"../../ReplicatedStorage/Shared/GiantRealm/GiantFollowerProxyState"
)

local sharedFolder = makeNode("Shared")
addChild(sharedFolder, "Config", configFolder)
addChild(sharedFolder, "GiantRealm", giantRealmFolder)

local replicatedStorage = makeNode("ReplicatedStorage", "ReplicatedStorage")
addChild(replicatedStorage, "Shared", sharedFolder)

local playersService: any = {
	PlayerRemoving = {
		Connect = function(_signal: any, _callback: (any) -> ()) end,
	},
}

local fakeGame: any = {}
function fakeGame:GetService(serviceName: string): any
	if serviceName == "ReplicatedStorage" then
		return replicatedStorage
	end
	if serviceName == "Players" then
		return playersService
	end
	return nil
end

game = fakeGame
local currentTime = 200
local trailSnapshots: any = {}
globalEnv._TinyfolkStatusService_QueryAPI = {
	GetAllTrailSnapshots = function(_now: number): any
		return trailSnapshots
	end,
}
local remoteControlOperatingByUserId: { [number]: boolean } = {}
globalEnv._RemoteControlStationService_QueryAPI = {
	IsGiantOperatingStation = function(userId: number): boolean
		return remoteControlOperatingByUserId[userId] == true
	end,
}

local serviceFactory = require("../src/ServerScriptService/Services/GiantFollowerProxyService.server")
local service = serviceFactory(fakeGame, {
	clock = function()
		return currentTime
	end,
})

local giant = MockPlayer.new(901, "FollowerProxyGiant", { role = "Giant" })
local tinyfolk = MockPlayer.new(902, "FollowerProxyTinyfolk", { role = "Tinyfolk" })

do
	local invalidMode = service.requestControlMode(giant, "invalid")
	assertEqual(invalidMode.accepted, false, "proxy mode rejects invalid mode")
	assertEqual(invalidMode.reason, "mode_invalid", "proxy invalid mode reason")

	local nonGiantAttempt = service.requestControlMode(tinyfolk, "proxy")
	assertEqual(nonGiantAttempt.accepted, false, "proxy mode rejects non-Giant requester")
	assertEqual(nonGiantAttempt.reason, "requester_not_giant", "proxy non-Giant rejection reason")
end

do
	currentTime = 208
	remoteControlOperatingByUserId[giant.UserId] = true
	local stationConflict = service.requestControlMode(giant, "proxy")
	assertEqual(stationConflict.accepted, false, "proxy mode rejects while remote-control station is occupied")
	assertEqual(stationConflict.reason, "remote_control_active", "proxy remote-control ownership conflict reason")
	remoteControlOperatingByUserId[giant.UserId] = false

	local switched = globalEnv._GiantFollowerProxyService_QueryAPI.RequestControlMode(giant, "proxy")
	assertEqual(switched.accepted, true, "proxy mode accepts valid Giant control switch")
	assertTrue(
		globalEnv._GiantFollowerProxyService_QueryAPI.IsProxyControlActive(giant.UserId),
		"proxy mode becomes active"
	)
end

do
	trailSnapshots = {
		[1001] = {
			intensity = 0.7,
			updatedAt = currentTime,
			primaryDirection = "east",
		},
		[1002] = {
			intensity = 0.4,
			updatedAt = currentTime,
			primaryDirection = "north",
		},
		[1003] = {
			intensity = 0.9,
			updatedAt = currentTime - 20,
			primaryDirection = "west",
		},
	}
	local snapshot = service.getSnapshot(giant.UserId)
	assertEqual(snapshot.proxyEnabled, true, "proxy snapshot reports active proxy mode")
	assertEqual(snapshot.pressureBand, "pressure", "proxy snapshot reports coarse pressure band")
	assertEqual(snapshot.pressureDirection, "east", "proxy snapshot reports coarse direction only")
	assertEqual(snapshot.trackedCount, 2, "proxy snapshot caps tracked tinyfolk candidates")
end

do
	currentTime = 215
	local switchBack = service.requestControlMode(giant, "direct")
	assertEqual(switchBack.accepted, true, "proxy mode allows switching back to direct control")
	assertEqual(switchBack.snapshot.proxyEnabled, false, "switching to direct disables proxy mode")
	assertEqual(switchBack.snapshot.pressureBand, "none", "direct mode clears proxy pressure output")
end

print("giant_follower_proxy_service_runtime_entrypoint: all checks passed")
