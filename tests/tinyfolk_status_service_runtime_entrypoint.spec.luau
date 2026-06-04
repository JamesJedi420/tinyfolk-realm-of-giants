--!nocheck
--!nolint BuiltinGlobalWrite
-- selene: allow(global_usage)
local TinyfolkStatusConfig = require("../src/ReplicatedStorage/Shared/Config/TinyfolkStatusConfig")
local globalEnv: any = getfenv()

local function assertTrue(condition: boolean, label: string)
	if not condition then
		error(string.format("FAIL [%s]: expected true, got false", label))
	end
	print(string.format("PASS [%s]", label))
end

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(string.format("FAIL [%s]: expected %q got %q", label, tostring(expected), tostring(actual)))
	end
	print(string.format("PASS [%s]", label))
end

local function contains(text: string?, needle: string): boolean
	return type(text) == "string" and string.find(text, needle, 1, true) ~= nil
end

local function makeNode(name: string, className: string?, fullName: string?)
	local node: any = {
		Name = name,
		ClassName = className or "Folder",
		_FullName = fullName or name,
		_Children = {},
	}

	function node.IsA(self: any, expectedClass: string): boolean
		return self.ClassName == expectedClass
	end

	function node.FindFirstChild(self: any, childName: string): any
		return self._Children[childName]
	end

	function node.WaitForChild(self: any, childName: string, _timeout: number?): any
		return self._Children[childName]
	end

	function node.GetChildren(self: any): { any }
		local children: { any } = {}
		for _, child in pairs(self._Children) do
			table.insert(children, child)
		end
		return children
	end

	function node.SetAttribute(self: any, attributeName: string, value: any)
		self._Attributes = self._Attributes or {}
		self._Attributes[attributeName] = value
	end

	function node.GetAttribute(self: any, attributeName: string): any
		self._Attributes = self._Attributes or {}
		return self._Attributes[attributeName]
	end

	return node
end

local function addChild(parent: any, childName: string, child: any)
	parent._Children[childName] = child
	child.Parent = parent
end

local replicatedStorage = makeNode("ReplicatedStorage", "ReplicatedStorage", "ReplicatedStorage")
local sharedFolder = makeNode("Shared", "Folder", "ReplicatedStorage.Shared")
local configFolder = makeNode("Config", "Folder", "ReplicatedStorage.Shared.Config")
local tinyfolkStatusFolder = makeNode("TinyfolkStatus", "Folder", "ReplicatedStorage.Shared.TinyfolkStatus")

configFolder._Children["RoleConfig"] = "../../ReplicatedStorage/Shared/Config/RoleConfig"
configFolder._Children["TinyfolkStatusConfig"] = "../../ReplicatedStorage/Shared/Config/TinyfolkStatusConfig"
tinyfolkStatusFolder._Children["TimedConditionStateLogic"] =
	"../../ReplicatedStorage/Shared/TinyfolkStatus/TimedConditionStateLogic"
tinyfolkStatusFolder._Children["GiantThreatStageLogic"] =
	"../../ReplicatedStorage/Shared/TinyfolkStatus/GiantThreatStageLogic"
tinyfolkStatusFolder._Children["RaidStatusProjection"] =
	"../../ReplicatedStorage/Shared/TinyfolkStatus/RaidStatusProjection"
tinyfolkStatusFolder._Children["TrailPressureLogic"] =
	"../../ReplicatedStorage/Shared/TinyfolkStatus/TrailPressureLogic"

addChild(sharedFolder, "Config", configFolder)
addChild(sharedFolder, "TinyfolkStatus", tinyfolkStatusFolder)
addChild(replicatedStorage, "Shared", sharedFolder)

local _playerRemovingConnections: { (any) -> () } = {}
local _heartbeatConnections: { (any) -> () } = {}
local playersService: any = {
	Name = "Players",
	ClassName = "Players",
	_playerList = {},
	PlayerRemoving = {
		Connect = function(_signal: any, callback: (any) -> ())
			table.insert(_playerRemovingConnections, callback)
		end,
	},
	GetPlayers = function(self: any): { any }
		return self._playerList
	end,
}

local runService: any = {
	Name = "RunService",
	ClassName = "RunService",
	Heartbeat = {
		Connect = function(_signal: any, callback: () -> ())
			table.insert(_heartbeatConnections, callback)
		end,
	},
}

local fakeGame = {}
function fakeGame:GetService(serviceName: string): any
	if serviceName == "Players" then
		return playersService
	end
	if serviceName == "RunService" then
		return runService
	end
	if serviceName == "ReplicatedStorage" then
		return replicatedStorage
	end
	error(string.format("unsupported service: %s", serviceName))
end

game = fakeGame

local function makePlayer(userId: number)
	local humanoid = {
		Health = 100,
	}
	local rootPart = {
		Name = "HumanoidRootPart",
		ClassName = "BasePart",
		Position = { x = 24, y = 0, z = 24, X = 24, Y = 0, Z = 24 },
	}
	function rootPart.IsA(self: any, expectedClass: string): boolean
		return self.ClassName == expectedClass
	end
	local character = {
		FindFirstChildOfClass = function(_self: any, className: string): any
			if className == "Humanoid" then
				return humanoid
			end
			return nil
		end,
		FindFirstChild = function(_self: any, childName: string): any
			if childName == "HumanoidRootPart" then
				return rootPart
			end
			return nil
		end,
	}
	local attributes = {
		Role = "Tinyfolk",
	}
	return {
		UserId = userId,
		Character = character,
		GetAttribute = function(_self: any, attributeName: string): any
			return attributes[attributeName]
		end,
		SetAttribute = function(_self: any, attributeName: string, value: any)
			attributes[attributeName] = value
		end,
	}
end

local function makeRolePlayer(
	userId: number,
	role: string,
	position: { x: number, y: number, z: number, X: number, Y: number, Z: number }
)
	local humanoid = {
		Health = 100,
	}
	local rootPart = {
		Name = "HumanoidRootPart",
		ClassName = "BasePart",
		Position = position,
	}
	function rootPart.IsA(self: any, expectedClass: string): boolean
		return self.ClassName == expectedClass
	end
	local character = {
		FindFirstChildOfClass = function(_self: any, className: string): any
			if className == "Humanoid" then
				return humanoid
			end
			return nil
		end,
		FindFirstChild = function(_self: any, childName: string): any
			if childName == "HumanoidRootPart" then
				return rootPart
			end
			return nil
		end,
	}
	local attributes = {
		Role = role,
	}
	return {
		UserId = userId,
		Character = character,
		GetAttribute = function(_self: any, attributeName: string): any
			return attributes[attributeName]
		end,
		SetAttribute = function(_self: any, attributeName: string, value: any)
			attributes[attributeName] = value
		end,
	}
end

local testPlayer = makePlayer(501)
local giantPlayer = makeRolePlayer(900, "Giant", { x = 30, y = 0, z = 24, X = 30, Y = 0, Z = 24 })
playersService._playerList = { testPlayer, giantPlayer }

local trapContactCalls: { any } = {}
local trapShouldTrigger = true
globalEnv._GiantBuildModeService_QueryAPI = {
	ResolveSnareTrapContact = function(userId: number, position: any, now: number?)
		table.insert(trapContactCalls, {
			userId = userId,
			position = position,
			now = now,
		})
		if not trapShouldTrigger then
			return {
				accepted = false,
				reason = "snare_trap_not_triggered",
				trap = nil,
			}
		end
		return {
			accepted = true,
			reason = "triggered",
			trap = {
				structureId = "GiantStructure_Runtime_Snare_A",
			},
		}
	end,
}

local serviceLoaded, serviceError = pcall(function()
	require("../src/ServerScriptService/Services/TinyfolkStatusService.server")
end)
if not serviceLoaded then
	error(string.format("FAIL [tinyfolk status service loads]: %s", tostring(serviceError)))
end

local service = require("../src/ServerScriptService/Services/TinyfolkStatusService.server")
local snapshot = service.ResolveNow(testPlayer, 250)

assertTrue(#trapContactCalls == 1, "status tick queries snare trap contact once")
assertEqual(trapContactCalls[1].userId, testPlayer.UserId, "snare trap contact uses player user id")
assertEqual(snapshot.stunActive, true, "snare trap contact applies stun active state")
assertTrue(snapshot.stunUntil > 250, "snare trap contact sets stun duration")

local attributes = TinyfolkStatusConfig.Attributes
assertEqual(testPlayer:GetAttribute(attributes.StunActive), true, "player attribute mirrors stun active state")
assertTrue(testPlayer:GetAttribute(attributes.StunUntil) > 250, "player attribute mirrors stun duration")

local statusQueryApi = globalEnv._TinyfolkStatusService_QueryAPI
assertTrue(
	type(statusQueryApi.ClearConditionForUserId) == "function",
	"status query API exposes ClearConditionForUserId"
)
trapShouldTrigger = false
local clearedSnapshot = statusQueryApi.ClearConditionForUserId(testPlayer.UserId, "stun", 252)
assertTrue(clearedSnapshot ~= nil, "clear condition by user id returns snapshot")
assertEqual(clearedSnapshot.stunActive, false, "clear condition by user id clears stun")

assertEqual(
	testPlayer:GetAttribute(attributes.RaidHudThreatStage),
	"critical",
	"raid threat stage reflects nearby giant pressure"
)

giantPlayer.Character.FindFirstChild = function(_self: any, childName: string): any
	if childName == "HumanoidRootPart" then
		return {
			Name = "HumanoidRootPart",
			ClassName = "BasePart",
			Position = { x = 999, y = 0, z = 999, X = 999, Y = 0, Z = 999 },
			IsA = function(self: any, expectedClass: string): boolean
				return self.ClassName == expectedClass
			end,
		}
	end
	return nil
end

local decayedSnapshot = service.ResolveNow(testPlayer, 261)
assertEqual(decayedSnapshot.raidThreatStage, "pressure", "raid threat stage decays one step at a time")

testPlayer:SetAttribute("CaptureActive", true)
testPlayer:SetAttribute("CaptureCustodianUserId", 900)
testPlayer:SetAttribute("CaptureExpiresAt", 275)
service.ResolveNow(testPlayer, 270)
testPlayer:SetAttribute("CaptureActive", false)
testPlayer:SetAttribute("CaptureCustodianUserId", nil)
testPlayer:SetAttribute("CaptureLastReason", "released")
service.ResolveNow(testPlayer, 271)

assertTrue(
	contains(testPlayer:GetAttribute(attributes.RaidHudSummary), "released|custody|positive"),
	"released terminal remains in self raid hud summary"
)
assertEqual(
	testPlayer:GetAttribute(attributes.RaidHudCustodyState),
	"released",
	"released terminal updates custody state"
)

service.ResolveNow(testPlayer, 276)
assertTrue(
	not contains(testPlayer:GetAttribute(attributes.RaidHudSummary), "released|custody|positive"),
	"released terminal expires from self raid hud summary"
)

testPlayer:SetAttribute("CaptureActive", true)
testPlayer:SetAttribute("CaptureCustodianUserId", 900)
testPlayer:SetAttribute("CaptureExpiresAt", 286)
testPlayer:SetAttribute("CaptureLastReason", nil)
service.ResolveNow(testPlayer, 285)
testPlayer:SetAttribute("CaptureActive", false)
testPlayer:SetAttribute("CaptureCustodianUserId", nil)
service.ResolveNow(testPlayer, 287)

assertTrue(
	contains(testPlayer:GetAttribute(attributes.RaidHudSummary), "expired|custody|info"),
	"expired terminal inferred from elapsed capture expiry"
)

local teammatePlayer = makePlayer(502)
playersService._playerList = { testPlayer, teammatePlayer, giantPlayer }
teammatePlayer:SetAttribute("CaptureActive", true)
teammatePlayer:SetAttribute("CaptureCustodianUserId", 900)
teammatePlayer:SetAttribute("CaptureExpiresAt", 286)
service.ResolveNow(teammatePlayer, 280)
teammatePlayer:SetAttribute("CaptureActive", false)
teammatePlayer:SetAttribute("CaptureCustodianUserId", nil)
teammatePlayer:SetAttribute("RescueContractLastReason", "rescued")
service.ResolveNow(testPlayer, 281)

assertTrue(
	contains(
		testPlayer:GetAttribute(attributes.RaidHudTeammateActivity),
		"teammate_rescued_502|teammate_activity|positive"
	),
	"rescued terminal remains in teammate raid hud activity"
)
