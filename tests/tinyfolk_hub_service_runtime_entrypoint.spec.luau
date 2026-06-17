--!nocheck
--!nolint BuiltinGlobalWrite

local RoleConfig = require("../src/ReplicatedStorage/Shared/Config/RoleConfig")
local EscapeConfig = require("../src/ReplicatedStorage/Shared/Config/EscapeConfig")
local TinyfolkHubConfig = require("../src/ReplicatedStorage/Shared/Config/TinyfolkHubConfig")
local RealmAssignmentProfileState = require("../src/ReplicatedStorage/Shared/GiantRealm/RealmAssignmentProfileState")
local RealmTransferState = require("../src/ReplicatedStorage/Shared/GiantRealm/RealmTransferState")

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(string.format("FAIL [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual)))
	end
end

local function assertTrue(condition: boolean, label: string)
	assertEqual(condition, true, label)
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

local function makePlayer(userId: number)
	local attributes: { [string]: any } = {}
	local characterAdded = makeSignal()
	local player: any = {
		UserId = userId,
		Name = "Player" .. tostring(userId),
		Character = nil,
		CharacterAdded = characterAdded,
	}

	function player.SetAttribute(_self: any, attributeName: string, value: any)
		attributes[attributeName] = value
	end

	function player.GetAttribute(_self: any, attributeName: string): any
		return attributes[attributeName]
	end

	function player:GetAttributeChangedSignal(_attributeName: string): any
		return makeSignal()
	end

	return player
end

local sharedFolder = {
	Name = "Shared",
	WaitForChild = function(_self: any, childName: string): any
		if childName == "Config" then
			return {
				WaitForChild = function(_inner: any, configName: string): any
					if configName == "EscapeConfig" then
						return "../../ReplicatedStorage/Shared/Config/EscapeConfig"
					end
					if configName == "RoleConfig" then
						return "../../ReplicatedStorage/Shared/Config/RoleConfig"
					end
					if configName == "TinyfolkHubConfig" then
						return "../../ReplicatedStorage/Shared/Config/TinyfolkHubConfig"
					end
					error(configName)
				end,
			}
		end
		if childName == "GiantRealm" then
			return {
				WaitForChild = function(_inner: any, moduleName: string): any
					if moduleName == "RealmAssignmentProfileState" then
						return "../../ReplicatedStorage/Shared/GiantRealm/RealmAssignmentProfileState"
					end
					if moduleName == "RealmTransferState" then
						return "../../ReplicatedStorage/Shared/GiantRealm/RealmTransferState"
					end
					error(moduleName)
				end,
			}
		end
		if childName == "TinyfolkHub" then
			return {
				WaitForChild = function(_inner: any, moduleName: string): any
					if moduleName == "TinyfolkHubState" then
						return "../../ReplicatedStorage/Shared/TinyfolkHub/TinyfolkHubState"
					end
					error(moduleName)
				end,
			}
		end
		error(childName)
	end,
}

local replicatedStorage = {
	Name = "ReplicatedStorage",
	WaitForChild = function(_self: any, childName: string): any
		if childName == "Shared" then
			return sharedFolder
		end
		error(childName)
	end,
}

local player = makePlayer(5001)
player:SetAttribute("Role", RoleConfig.Roles.Tinyfolk)
player:SetAttribute("RoleLocked", true)

local playerAdded = makeSignal()
local playersService: any = {
	PlayerAdded = playerAdded,
	GetPlayers = function(): { any }
		return { player }
	end,
}

local fakeGame: any = {
	GetService = function(_self: any, serviceName: string): any
		if serviceName == "Players" then
			return playersService
		end
		if serviceName == "ReplicatedStorage" then
			return replicatedStorage
		end
		error(serviceName)
	end,
}

game = fakeGame

local assignmentByUserId: { [number]: any } = {
	[5001] = RealmTransferState.NewSharedHubAssignment(10),
}
local transitionCalls = 0

_G._RealmTransferAssignmentService_QueryAPI = {
	GetAssignmentSnapshot = function(userId: number): any
		local assignment = assignmentByUserId[userId]
		if assignment == nil then
			return {
				accepted = false,
				reason = "profile_not_loaded",
			}
		end
		return {
			accepted = true,
			reason = "accepted",
			assignment = assignment,
		}
	end,
	ApplyTransition = function(userId: number, input: any): any
		transitionCalls += 1
		if input.operation == RealmTransferState.Operations.SetSharedHub then
			assignmentByUserId[userId] = RealmTransferState.NewSharedHubAssignment(input.now)
			return {
				accepted = true,
				reason = "accepted",
				assignment = assignmentByUserId[userId],
			}
		end
		return {
			accepted = false,
			reason = "unsupported_operation",
		}
	end,
}

require("../src/ServerScriptService/Services/TinyfolkHubService.server")

local hubApi: any = _G._TinyfolkHubService_QueryAPI
assertTrue(type(hubApi) == "table", "hub service exposes query api")

playerAdded:Fire(player)

assertEqual(
	player:GetAttribute(TinyfolkHubConfig.LocationCategoryAttribute),
	RealmAssignmentProfileState.LocationCategory.SharedHub,
	"hub service projects shared hub category"
)
assertEqual(player:GetAttribute(TinyfolkHubConfig.InHubAttribute), true, "hub service marks in hub")
assertEqual(player:GetAttribute(EscapeConfig.SafeZoneAttribute), true, "hub service applies safe zone")
assertEqual(
	player:GetAttribute(EscapeConfig.SafeZoneTypeAttribute),
	EscapeConfig.SafeZoneTypes.SharedHub,
	"hub service applies shared hub safe zone type"
)
assertTrue(transitionCalls >= 1, "hub service ensures shared hub assignment")

assignmentByUserId[5001] = {
	locationCategory = RealmAssignmentProfileState.LocationCategory.GiantRealm,
	realmId = "giant_realm_9001",
	realmOwnerUserId = 9001,
	assignmentReason = nil,
	updatedAt = 20,
}
local syncResult = hubApi.SyncHubPresenceForUserId(5001)
assertTrue(syncResult.accepted, "sync succeeds for giant realm assignment player")
assertEqual(player:GetAttribute(EscapeConfig.SafeZoneAttribute), false, "giant realm assignment clears hub safe zone")
assertEqual(player:GetAttribute(TinyfolkHubConfig.InHubAttribute), false, "giant realm assignment clears in hub flag")

local raidEligibility = hubApi.ResolveActivityEligibility(5001, TinyfolkHubConfig.Activities.RaidBoard)
assertEqual(raidEligibility.accepted, false, "raid board denied outside shared hub")
assertEqual(raidEligibility.reason, "not_in_shared_hub", "raid board denial reason")

assignmentByUserId[5001] = RealmTransferState.NewSharedHubAssignment(30)
hubApi.SyncHubPresenceForUserId(5001)
local raidAccepted = hubApi.ResolveActivityEligibility(5001, TinyfolkHubConfig.Activities.RaidBoard)
assertTrue(raidAccepted.accepted, "raid board allowed after returning to shared hub")

print("tinyfolk_hub_service_runtime_entrypoint: all checks passed")
