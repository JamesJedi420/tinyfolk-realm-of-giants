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

local configFolder = makeNode("Config", "Folder")
addChild(configFolder, "CaptureConfig", "../../ReplicatedStorage/Shared/Config/CaptureConfig")
addChild(configFolder, "RoleConfig", "../../ReplicatedStorage/Shared/Config/RoleConfig")

local giantRealmFolder = makeNode("GiantRealm", "Folder")
addChild(
	giantRealmFolder,
	"AntiGuardingContainmentPressureState",
	"../../ReplicatedStorage/Shared/GiantRealm/AntiGuardingContainmentPressureState"
)
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

local remotesFolder = makeNode("Remotes", "Folder")
addChild(remotesFolder, "CaptivityStruggleRequest", makeRemoteEvent("CaptivityStruggleRequest"))
addChild(remotesFolder, "CaptivityAllyAssistRequest", makeRemoteEvent("CaptivityAllyAssistRequest"))
addChild(replicatedStorage, "Remotes", remotesFolder)

local captureZonesFolder = makeNode("CaptureZones", "Folder")
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
	if serviceName == "RunService" then
		return {
			Heartbeat = makeSignal(),
		}
	end
	error("unsupported service " .. serviceName)
	return nil
end

game = fakeGame

local captureRecords: { [number]: any } = {}
local custodyEndCalls: { any } = {}

local function resetCaptureRuntime()
	captureRecords = {}
	custodyEndCalls = {}
end

_G._CaptureService_QueryAPI = {
	GetTargetCapture = function(targetUserId: number, _at: number?): any
		return captureRecords[targetUserId]
	end,
	GetAllCaptures = function(_at: number?): { any }
		local captures: { any } = {}
		for _, record in pairs(captureRecords) do
			table.insert(captures, record)
		end
		return captures
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
}

require("../src/ServerScriptService/Services/CaptivityEscapeService.server")
require("../src/ServerScriptService/Services/AntiGuardingContainmentPressureService.server")

local pressureApi = _G._AntiGuardingContainmentPressureService_QueryAPI
local escapeApi = _G._CaptivityEscapeService_QueryAPI
assertTrue(type(pressureApi) == "table", "anti-guarding query api exposed")
assertTrue(type(escapeApi.ApplyAntiGuardingCounterplay) == "function", "captivity escape counterplay seam exposed")

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
	pressureApi.ResetForTests()
	escapeApi.ResetForTests()
	resetCaptureRuntime()
end

resetPlayers()
local target = makePlayer(4001, "Tinyfolk", { x = 0, y = 0, z = 0 })
local custodian = makePlayer(4002, "Giant", { x = 0, y = 0, z = 0 })
captureRecords[4001] = {
	custodianUserId = 4002,
	targetUserId = 4001,
	startedAt = 1,
	expiresAt = 20,
	captivityAnchorAt = 1,
	containmentPhase = "contained",
	containedAt = 10,
}

local graceTick = pressureApi.TickContainedTarget(4001, 12)
assertTrue(graceTick.accepted, "grace tick accepted")
assertEqual(graceTick.snapshot.phase, "grace", "grace phase during placement window")
assertEqual(target:GetAttribute("AntiGuardingPressure"), 0, "grace projects zero pressure")

local accumulating = pressureApi.TickContainedTarget(4001, 14)
assertTrue(accumulating.accepted, "accumulating tick accepted")
assertEqual(accumulating.snapshot.phase, "accumulating", "accumulating phase after grace")
assertTrue((accumulating.snapshot.pressure :: number) > 0, "pressure increases after grace")

custodian.Character.FindFirstChild = function(_self: any, name: string): any
	if name == "HumanoidRootPart" then
		return {
			Position = { x = 100, y = 0, z = 0 },
			IsA = function(_part: any, className: string): boolean
				return className == "BasePart"
			end,
		}
	end
	return nil
end
local decaying = pressureApi.TickContainedTarget(4001, 14.5)
assertTrue(decaying.accepted, "decay tick accepted")
assertEqual(decaying.snapshot.phase, "decaying", "decay phase when custodian leaves")
assertTrue((decaying.snapshot.pressure :: number) < (accumulating.snapshot.pressure :: number), "pressure decays away")

custodian.Character.FindFirstChild = function(_self: any, name: string): any
	if name == "HumanoidRootPart" then
		return {
			Position = { x = 0, y = 0, z = 0 },
			IsA = function(_part: any, className: string): boolean
				return className == "BasePart"
			end,
		}
	end
	return nil
end

resetPlayers()
target = makePlayer(4101, "Tinyfolk", { x = 0, y = 0, z = 0 })
makePlayer(4102, "Giant", { x = 0, y = 0, z = 0 })
captureRecords[4101] = {
	custodianUserId = 4102,
	targetUserId = 4101,
	startedAt = 1,
	expiresAt = 20,
	captivityAnchorAt = 1,
	containmentPhase = "contained",
	containedAt = 0,
}
pressureApi.TickContainedTarget(4101, 4)
local counterplay = pressureApi.TickContainedTarget(4101, 10)
assertTrue(counterplay.accepted, "counterplay tick accepted")
assertEqual(counterplay.reason, "anti_guarding_counterplay_release", "counterplay release reason")
assertEqual(#custodyEndCalls, 1, "counterplay resolves custody end")
assertEqual(custodyEndCalls[1].endReason, "released", "counterplay custody end reason")
assertEqual(captureRecords[4101], nil, "counterplay clears capture record")
assertEqual(target:GetAttribute("AntiGuardingPressurePhase"), "consumed", "counterplay marks consumed phase")

print("anti_guarding_containment_pressure_service_runtime_entrypoint: all checks passed")
