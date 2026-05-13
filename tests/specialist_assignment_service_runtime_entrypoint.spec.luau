--!strict

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

local warns: { string } = {}
local originalWarn = warn
warn = function(...: any)
	local packed = table.pack(...)
	local parts: { string } = {}
	for i = 1, packed.n :: number do
		table.insert(parts, tostring(packed[i]))
	end
	local line = table.concat(parts, " ")
	table.insert(warns, line)
	originalWarn(...)
end

local function sawWarnContaining(fragment: string): boolean
	for _, line in ipairs(warns) do
		if string.find(line, fragment, 1, true) ~= nil then
			return true
		end
	end
	return false
end

local function makeSignal()
	local callbacks: { (...any) -> () } = {}
	return {
		Connect = function(_self: any, callback: (...any) -> ())
			table.insert(callbacks, callback)
			return {}
		end,
		Fire = function(_self: any, ...: any)
			for _, callback in ipairs(callbacks) do
				callback(...)
			end
		end,
	}
end

local function makeNode(name: string, className: string?, fullName: string?)
	local node: any = {
		Name = name,
		ClassName = className or "Folder",
		_FullName = fullName or name,
		_Children = {},
		_Attributes = {},
		Parent = nil,
	}

	function node.IsA(self: any, expectedClass: string): boolean
		return self.ClassName == expectedClass
	end

	function node.GetFullName(self: any): string
		return self._FullName
	end

	function node.FindFirstChild(self: any, childName: string): any
		return self._Children[childName]
	end

	function node.WaitForChild(self: any, childName: string, _timeout: number?): any
		return self._Children[childName]
	end

	function node.SetAttribute(self: any, attributeName: string, value: any)
		self._Attributes[attributeName] = value
	end

	function node.GetAttribute(self: any, attributeName: string): any
		return self._Attributes[attributeName]
	end

	return node
end

local function addChild(parent: any, childName: string, child: any)
	parent._Children[childName] = child
	if type(child) == "table" then
		child.Parent = parent
	end
end

local function makeRemoteEvent(remoteName: string)
	local remote: any = {
		Name = remoteName,
		ClassName = "RemoteEvent",
		_Handler = nil,
		_ClientPayload = nil,
	}

	function remote.IsA(self: any, expectedClass: string): boolean
		return self.ClassName == expectedClass
	end

	remote.OnServerEvent = {
		Connect = function(_signal: any, handler: (Player, any) -> ())
			remote._Handler = handler
		end,
	}

	function remote.FireServer(self: any, player: Player, payload: any)
		if self._Handler == nil then
			error(string.format("remote %s handler not connected", self.Name))
		end
		self._Handler(player, payload)
	end

	function remote.FireClient(self: any, _player: Player, payload: any)
		self._ClientPayload = payload
	end

	return remote
end

local function makePlayer(userId: number)
	local attributes: { [string]: any } = {}
	local attributeChangedSignals: { [string]: any } = {}
	local player: any = {
		UserId = userId,
		Name = "Player" .. tostring(userId),
	}

	function player.SetAttribute(self: any, attributeName: string, value: any)
		attributes[attributeName] = value
		local signal = attributeChangedSignals[attributeName]
		if signal ~= nil then
			signal:Fire()
		end
	end

	function player.GetAttribute(_self: any, attributeName: string): any
		return attributes[attributeName]
	end

	function player.GetAttributeChangedSignal(_self: any, attributeName: string): any
		local existing = attributeChangedSignals[attributeName]
		if existing ~= nil then
			return existing
		end

		local created = makeSignal()
		attributeChangedSignals[attributeName] = created
		return created
	end

	return player
end

local assignRemote = makeRemoteEvent("SpecialistAssignRequest")
local clearRemote = makeRemoteEvent("SpecialistClearRequest")
local debugRequestRemote = makeRemoteEvent("SpecialistDebugStateRequest")
local debugResponseRemote = makeRemoteEvent("SpecialistDebugStateResponse")

local remotesFolder = makeNode("Remotes", "Folder", "ReplicatedStorage.Remotes")
addChild(remotesFolder, "SpecialistAssignRequest", assignRemote)
addChild(remotesFolder, "SpecialistClearRequest", clearRemote)
addChild(remotesFolder, "SpecialistDebugStateRequest", debugRequestRemote)
addChild(remotesFolder, "SpecialistDebugStateResponse", debugResponseRemote)

local configFolder = makeNode("Config", "Folder", "ReplicatedStorage.Shared.Config")
addChild(configFolder, "RoleConfig", "../../ReplicatedStorage/Shared/Config/RoleConfig")
addChild(configFolder, "SpecialistConfig", "../../ReplicatedStorage/Shared/Config/SpecialistConfig")
addChild(configFolder, "StationConfig", "../../ReplicatedStorage/Shared/Config/StationConfig")
addChild(configFolder, "ShrineConfig", "../../ReplicatedStorage/Shared/Config/ShrineConfig")

local sharedFolder = makeNode("Shared", "Folder", "ReplicatedStorage.Shared")
addChild(sharedFolder, "Config", configFolder)

local replicatedStorage = makeNode("ReplicatedStorage", "ReplicatedStorage", "ReplicatedStorage")
addChild(replicatedStorage, "Shared", sharedFolder)
addChild(replicatedStorage, "Remotes", remotesFolder)

local restoreValid = makePlayer(3001)
local missingStored = makePlayer(3002)
local invalidStored = makePlayer(3003)
local readFailure = makePlayer(3004)
local invalidStationType = makePlayer(3005)
local staleAssignedStation = makePlayer(3006)
local assignOk = makePlayer(4001)
local assignUpdateFailure = makePlayer(4002)
local clearOk = makePlayer(4003)
local clearUpdateFailure = makePlayer(4004)
local cooldownPlayer = makePlayer(4005)
local malformedPlayer = makePlayer(4006)

local playersList = {
	restoreValid,
	missingStored,
	invalidStored,
	readFailure,
	invalidStationType,
	staleAssignedStation,
	assignOk,
	assignUpdateFailure,
	clearOk,
	clearUpdateFailure,
	cooldownPlayer,
	malformedPlayer,
}

local playerAdded = makeSignal()
local playerRemoving = makeSignal()

local playersService: any = {
	Name = "Players",
	ClassName = "Players",
	PlayerAdded = playerAdded,
	PlayerRemoving = playerRemoving,
}

function playersService:GetPlayers(): { Player }
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
	error(string.format("unsupported service: %s", serviceName))
	return nil
end

game = fakeGame

local RoleConfig = require("../src/ReplicatedStorage/Shared/Config/RoleConfig")
local SpecialistConfig = require("../src/ReplicatedStorage/Shared/Config/SpecialistConfig")
local ProfilePersistenceGateway = require("../src/ServerScriptService/Services/ProfilePersistenceGateway")

for _, player in ipairs(playersList) do
	player:SetAttribute("Role", RoleConfig.Roles.Tinyfolk)
end

local profileDataByUserId: { [number]: any } = {
	[3001] = {
		schemaVersion = 1,
		userId = 3001,
		specialistPreference = {
			specialistRole = SpecialistConfig.SpecialistRoles.Miner,
			assignedStationId = "MiningStation_A",
		},
		marker = "restore-valid",
	},
	[3002] = {
		schemaVersion = 1,
		userId = 3002,
		marker = "missing",
	},
	[3003] = {
		schemaVersion = 1,
		userId = 3003,
		specialistPreference = {
			specialistRole = "InvalidSpecialistRole",
		},
		marker = "invalid",
	},
	[3005] = {
		schemaVersion = 1,
		userId = 3005,
		specialistPreference = {
			specialistRole = SpecialistConfig.SpecialistRoles.Woodcutter,
			assignedStationId = 100,
		},
		marker = "invalid-station-type",
	},
	[3006] = {
		schemaVersion = 1,
		userId = 3006,
		specialistPreference = {
			specialistRole = SpecialistConfig.SpecialistRoles.Woodcutter,
			assignedStationId = "Shrine_A",
		},
		marker = "stale-station",
	},
	[4001] = {
		schemaVersion = 1,
		userId = 4001,
		marker = "assign-ok",
	},
	[4002] = {
		schemaVersion = 1,
		userId = 4002,
		marker = "assign-update-failure",
	},
	[4003] = {
		schemaVersion = 1,
		userId = 4003,
		specialistPreference = {
			specialistRole = SpecialistConfig.SpecialistRoles.Worshipper,
			assignedStationId = "Shrine_A",
		},
		marker = "clear-ok",
	},
	[4004] = {
		schemaVersion = 1,
		userId = 4004,
		specialistPreference = {
			specialistRole = SpecialistConfig.SpecialistRoles.Woodcutter,
			assignedStationId = "WorkStation_A",
		},
		marker = "clear-update-failure",
	},
	[4005] = {
		schemaVersion = 1,
		userId = 4005,
		marker = "cooldown",
	},
	[4006] = {
		schemaVersion = 1,
		userId = 4006,
		marker = "malformed",
	},
}

local readFailureByUserId: { [number]: boolean } = {
	[3004] = true,
}

local updateFailureByUserId: { [number]: boolean } = {
	[4002] = true,
	[4004] = true,
}

local updateCallCountByUserId: { [number]: number } = {}

ProfilePersistenceGateway.ResetForTests()
ProfilePersistenceGateway.GetLoadedPlayerProfileData = function(player: any): any
	if readFailureByUserId[player.UserId] == true then
		return {
			ok = false,
			operation = "GetLoadedPlayerProfileData",
			reason = "player_profile_not_loaded",
			profileKey = "PlayerProfile:" .. tostring(player.UserId),
		}
	end

	local data = profileDataByUserId[player.UserId]
	if type(data) ~= "table" then
		return {
			ok = false,
			operation = "GetLoadedPlayerProfileData",
			reason = "player_profile_not_loaded",
			profileKey = "PlayerProfile:" .. tostring(player.UserId),
		}
	end

	return {
		ok = true,
		operation = "GetLoadedPlayerProfileData",
		profileKey = "PlayerProfile:" .. tostring(player.UserId),
		data = cloneTable(data),
	}
end

ProfilePersistenceGateway.UpdateLoadedPlayerProfileData = function(player: any, updater: any): any
	if updateFailureByUserId[player.UserId] == true then
		return {
			ok = false,
			operation = "UpdateLoadedPlayerProfileData",
			reason = "player_profile_not_loaded",
			profileKey = "PlayerProfile:" .. tostring(player.UserId),
		}
	end

	local activeData = profileDataByUserId[player.UserId]
	if type(activeData) ~= "table" then
		return {
			ok = false,
			operation = "UpdateLoadedPlayerProfileData",
			reason = "player_profile_not_loaded",
			profileKey = "PlayerProfile:" .. tostring(player.UserId),
		}
	end

	if type(updater) ~= "function" then
		return {
			ok = false,
			operation = "UpdateLoadedPlayerProfileData",
			reason = "profile_update_updater_invalid",
			profileKey = "PlayerProfile:" .. tostring(player.UserId),
		}
	end

	local updateOk, newData = pcall(updater, cloneTable(activeData))
	if not updateOk or type(newData) ~= "table" then
		return {
			ok = false,
			operation = "UpdateLoadedPlayerProfileData",
			reason = "profile_update_failed",
			profileKey = "PlayerProfile:" .. tostring(player.UserId),
		}
	end

	profileDataByUserId[player.UserId] = cloneTable(newData)
	updateCallCountByUserId[player.UserId] = (updateCallCountByUserId[player.UserId] or 0) + 1

	return {
		ok = true,
		operation = "UpdateLoadedPlayerProfileData",
		profileKey = "PlayerProfile:" .. tostring(player.UserId),
		data = cloneTable(profileDataByUserId[player.UserId]),
	}
end

require("../src/ServerScriptService/Services/SpecialistAssignmentService.server")

assertEqual(
	restoreValid:GetAttribute("SpecialistRole"),
	SpecialistConfig.SpecialistRoles.Miner,
	"valid stored specialist role restores SpecialistRole on setup"
)
assertEqual(
	restoreValid:GetAttribute("SpecialistAssignedStationId"),
	"MiningStation_A",
	"valid stored assigned station restores when role-compatible"
)
assertEqual(
	restoreValid:GetAttribute("SpecialistLastAssignmentReason"),
	SpecialistConfig.AssignmentReasons.Initial,
	"restore keeps default assignment reason"
)

assertEqual(
	missingStored:GetAttribute("SpecialistRole"),
	SpecialistConfig.SpecialistRoles.None,
	"missing stored specialist role falls back to default"
)
assertEqual(
	missingStored:GetAttribute("SpecialistAssignedStationId"),
	nil,
	"missing stored assigned station falls back to nil"
)

assertEqual(
	invalidStored:GetAttribute("SpecialistRole"),
	SpecialistConfig.SpecialistRoles.None,
	"invalid stored specialist role falls back to default"
)
assertEqual(
	invalidStored:GetAttribute("SpecialistAssignedStationId"),
	nil,
	"invalid specialist role keeps assigned station nil"
)
assertTrue(sawWarnContaining("reason=invalid_specialist_role"), "invalid stored specialist role warning emitted")

assertEqual(
	invalidStationType:GetAttribute("SpecialistRole"),
	SpecialistConfig.SpecialistRoles.Woodcutter,
	"invalid assigned station type keeps stored specialist role restore behavior"
)
assertEqual(
	invalidStationType:GetAttribute("SpecialistAssignedStationId"),
	nil,
	"invalid assigned station type falls back to nil"
)
assertTrue(
	sawWarnContaining("reason=invalid_assigned_station_id_type"),
	"invalid assigned station type warning emitted"
)

assertEqual(
	staleAssignedStation:GetAttribute("SpecialistRole"),
	SpecialistConfig.SpecialistRoles.Woodcutter,
	"stale assigned station keeps stored specialist role restore behavior"
)
assertEqual(
	staleAssignedStation:GetAttribute("SpecialistAssignedStationId"),
	nil,
	"stale or incompatible assigned station falls back to nil"
)
assertTrue(
	sawWarnContaining("Specialist assigned station ignored userId=3006"),
	"stale assigned station warning emitted"
)

assertEqual(
	readFailure:GetAttribute("SpecialistRole"),
	SpecialistConfig.SpecialistRoles.None,
	"gateway read failure falls back to default"
)
assertEqual(
	readFailure:GetAttribute("SpecialistAssignedStationId"),
	nil,
	"gateway read failure keeps assigned station nil"
)
assertTrue(sawWarnContaining("Specialist role read failed userId=3004"), "gateway read failure warning emitted")

assignRemote:FireServer(assignOk, {
	specialistRole = SpecialistConfig.SpecialistRoles.Woodcutter,
	assignedStationId = "WorkStation_A",
})
assertEqual(
	assignOk:GetAttribute("SpecialistRole"),
	SpecialistConfig.SpecialistRoles.Woodcutter,
	"accepted assign sets SpecialistRole"
)
assertEqual(assignOk:GetAttribute("SpecialistAssignedStationId"), "WorkStation_A", "accepted assign sets station")
assertEqual(
	assignOk:GetAttribute("SpecialistLastAssignmentReason"),
	SpecialistConfig.AssignmentReasons.Assigned,
	"accepted assign sets assignment reason"
)
assertEqual(updateCallCountByUserId[4001], 2, "accepted assign updates role and assigned station via gateway")
assertEqual(
	profileDataByUserId[4001].specialistPreference.specialistRole,
	SpecialistConfig.SpecialistRoles.Woodcutter,
	"accepted assign persists specialist role"
)
assertEqual(
	profileDataByUserId[4001].specialistPreference.assignedStationId,
	"WorkStation_A",
	"accepted assign persists assigned station"
)
assertEqual(profileDataByUserId[4001].marker, "assign-ok", "updater touches only specialist preference data")

assignRemote:FireServer(assignUpdateFailure, {
	specialistRole = SpecialistConfig.SpecialistRoles.Miner,
	assignedStationId = "MiningStation_A",
})
assertEqual(
	assignUpdateFailure:GetAttribute("SpecialistRole"),
	SpecialistConfig.SpecialistRoles.Miner,
	"gateway update failure does not break accepted assign"
)
assertEqual(
	assignUpdateFailure:GetAttribute("SpecialistAssignedStationId"),
	"MiningStation_A",
	"gateway update failure does not break accepted assign station state"
)
assertEqual(updateCallCountByUserId[4002], nil, "failed assign update does not mutate profile snapshot")
assertTrue(sawWarnContaining("Specialist role update failed userId=4002"), "assign update failure warning emitted")
assertTrue(
	sawWarnContaining("Specialist assigned station update failed userId=4002"),
	"assign station update failure warning emitted"
)

clearRemote:FireServer(clearOk, nil)
assertEqual(
	clearOk:GetAttribute("SpecialistRole"),
	SpecialistConfig.SpecialistRoles.None,
	"accepted clear resets specialist role"
)
assertEqual(clearOk:GetAttribute("SpecialistAssignedStationId"), nil, "accepted clear resets station")
assertEqual(
	clearOk:GetAttribute("SpecialistLastAssignmentReason"),
	SpecialistConfig.AssignmentReasons.ClearedManual,
	"accepted clear keeps clear reason behavior"
)
assertEqual(updateCallCountByUserId[4003], 2, "accepted clear updates role and assigned station via gateway")
assertEqual(
	profileDataByUserId[4003].specialistPreference.specialistRole,
	SpecialistConfig.SpecialistRoles.None,
	"accepted clear persists neutral specialist role"
)
assertEqual(
	profileDataByUserId[4003].specialistPreference.assignedStationId,
	nil,
	"accepted clear persists assigned station nil"
)

clearRemote:FireServer(clearUpdateFailure, nil)
assertEqual(
	clearUpdateFailure:GetAttribute("SpecialistRole"),
	SpecialistConfig.SpecialistRoles.None,
	"gateway update failure does not break accepted clear"
)
assertEqual(
	clearUpdateFailure:GetAttribute("SpecialistAssignedStationId"),
	nil,
	"gateway update failure does not break accepted clear station state"
)
assertEqual(updateCallCountByUserId[4004], nil, "failed clear update does not mutate profile snapshot")
assertTrue(sawWarnContaining("Specialist role update failed userId=4004"), "clear update failure warning emitted")
assertTrue(
	sawWarnContaining("Specialist assigned station update failed userId=4004"),
	"clear station update failure warning emitted"
)

assignRemote:FireServer(malformedPlayer, "not-a-table")
assertEqual(
	malformedPlayer:GetAttribute("SpecialistRole"),
	SpecialistConfig.SpecialistRoles.None,
	"malformed assign rejection behavior unchanged"
)
assertEqual(updateCallCountByUserId[4006], nil, "malformed assign does not update profile")
assertTrue(sawWarnContaining("reason=malformed_payload"), "malformed payload warning emitted")

assignRemote:FireServer(cooldownPlayer, {
	specialistRole = SpecialistConfig.SpecialistRoles.Worshipper,
	assignedStationId = "Shrine_A",
})
assignRemote:FireServer(cooldownPlayer, {
	specialistRole = SpecialistConfig.SpecialistRoles.Worshipper,
	assignedStationId = "Shrine_A",
})
assertEqual(updateCallCountByUserId[4005], 2, "cooldown preserves one accepted assign with two gateway updates")
assertTrue(sawWarnContaining("reason=request_cooldown"), "cooldown rejection behavior unchanged")

print("specialist_assignment_service_runtime_entrypoint: all checks passed")
