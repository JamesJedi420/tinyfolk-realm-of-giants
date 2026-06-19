--!nocheck
--!nolint BuiltinGlobalWrite
-- selene: allow(global_usage)

local SpecialistConfig = require("../src/ReplicatedStorage/Shared/Config/SpecialistConfig")
local TinyfolkJobSchedulingConfig = require("../src/ReplicatedStorage/Shared/Config/TinyfolkJobSchedulingConfig")
local RoleConfig = require("../src/ReplicatedStorage/Shared/Config/RoleConfig")

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(string.format("FAIL [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual)))
	end
	print(string.format("PASS [%s]", label))
end

local function makePlayer(userId: number)
	local attributes: { [string]: any } = {
		Role = RoleConfig.Roles.Tinyfolk,
		SpecialistRole = SpecialistConfig.SpecialistRoles.None,
		SpecialistAssignedStationId = nil,
	}
	local player: any = {
		UserId = userId,
		Name = "Player" .. tostring(userId),
	}

	function player:GetAttribute(name: string): any
		return attributes[name]
	end

	function player:SetAttribute(name: string, value: any)
		attributes[name] = value
	end

	player._Attributes = attributes
	return player
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
		remote._ClientPayload = payload
	end

	return remote
end

Instance = {
	new = function(className: string): any
		if className == "Folder" then
			return {
				Name = "Folder",
				ClassName = "Folder",
				Parent = nil,
				_Children = {},
				IsA = function(self: any, expected: string)
					return self.ClassName == expected
				end,
				FindFirstChild = function(self: any, childName: string)
					return self._Children[childName]
				end,
			}
		end
		if className == "RemoteEvent" then
			return makeRemoteEvent("GeneratedRemote")
		end
		error(string.format("unsupported Instance.new(%q)", className))
	end,
} :: any

local configFolder: any = {
	WaitForChild = function(_self: any, childName: string)
		if childName == "RoleConfig" then
			return "../../ReplicatedStorage/Shared/Config/RoleConfig"
		end
		if childName == "CaptureConfig" then
			return "../../ReplicatedStorage/Shared/Config/CaptureConfig"
		end
		if childName == "TinyfolkJobSchedulingConfig" then
			return "../../ReplicatedStorage/Shared/Config/TinyfolkJobSchedulingConfig"
		end
		if childName == "SpecialistConfig" then
			return "../../ReplicatedStorage/Shared/Config/SpecialistConfig"
		end
		error("missing config child " .. childName)
	end,
}

local giantRealmFolder: any = {
	WaitForChild = function(_self: any, childName: string)
		if childName == "TinyfolkJobSchedulingState" then
			return "../../ReplicatedStorage/Shared/GiantRealm/TinyfolkJobSchedulingState"
		end
		error("missing giant realm child " .. childName)
	end,
}

local sharedFolder: any = {
	WaitForChild = function(_self: any, childName: string)
		if childName == "Config" then
			return configFolder
		end
		if childName == "GiantRealm" then
			return giantRealmFolder
		end
		error("missing shared child " .. childName)
	end,
}

local remotesFolder: any = {
	Name = "Remotes",
	ClassName = "Folder",
	Parent = nil,
	_Children = {},
	IsA = function(self: any, expected: string)
		return self.ClassName == expected
	end,
	FindFirstChild = function(self: any, childName: string)
		return self._Children[childName]
	end,
}

local replicatedStorage: any = {
	WaitForChild = function(_self: any, childName: string)
		if childName == "Shared" then
			return sharedFolder
		end
		if childName == "Remotes" then
			return remotesFolder
		end
		error("missing replicated child " .. childName)
	end,
	FindFirstChild = function(_self: any, childName: string)
		if childName == "Remotes" then
			return remotesFolder
		end
		return nil
	end,
}

local fakeGame = {}
function fakeGame:GetService(serviceName: string): any
	if serviceName == "ReplicatedStorage" then
		return replicatedStorage
	end
	if serviceName == "Players" then
		return {
			GetPlayers = function()
				return {}
			end,
			PlayerRemoving = {
				Connect = function() end,
			},
		}
	end
	error("unsupported service " .. serviceName)
end

game = fakeGame :: any

local woodcutter = makePlayer(8101)
local hauler = makePlayer(8102)
local playersList = { woodcutter, hauler }

local specialistAssignCalls: { any } = {}
_G._TinyfolkJobSchedulingService_DisableAutoStart = true
_G._TinyfolkJobSchedulingService_StartConfig = nil

require("../src/ServerScriptService/Services/TinyfolkJobSchedulingService.server")

local testHooks = _G._TinyfolkJobSchedulingService_TestHooks
local queryApi = _G._TinyfolkJobSchedulingService_QueryAPI

testHooks.SetPlayersService({
	GetPlayers = function()
		return playersList
	end,
	PlayerRemoving = {
		Connect = function() end,
	},
})
testHooks.SetStationQueryApi({
	ListStationDemandSnapshots = function()
		return {
			{
				stationId = "WorkStation_A",
				requiredSpecialistRole = SpecialistConfig.SpecialistRoles.Woodcutter,
				materialType = "Wood",
			},
		}
	end,
})
testHooks.SetSpecialistQueryApi({
	AssignForJobScheduling = function(
		player: any,
		specialistRole: string,
		assignedStationId: string?
	): (boolean, string)
		table.insert(specialistAssignCalls, {
			userId = player.UserId,
			specialistRole = specialistRole,
			assignedStationId = assignedStationId,
		})
		player:SetAttribute("SpecialistRole", specialistRole)
		player:SetAttribute("SpecialistAssignedStationId", assignedStationId)
		return true, "assigned"
	end,
})
testHooks.SetFlowSnapshotProvider(function()
	return {
		Wood = { produced = 6, inTransit = 0, stored = 0 },
		Stone = { produced = 0, inTransit = 0, stored = 0 },
		Food = { produced = 0, inTransit = 0, stored = 0 },
		Metal = { produced = 0, inTransit = 0, stored = 0 },
	}
end)
testHooks.SetShrineDemandProvider(function()
	return {}
end)
testHooks.SetGiantRealmActive(true)

local snapshot = queryApi.ProcessTick()
assertEqual(snapshot.assignmentCount, 2, "tick assigns specialist and haul jobs")
assertEqual(#specialistAssignCalls, 1, "specialist assignment applied once")
assertEqual(specialistAssignCalls[1].userId, 8101, "woodcutter player receives specialist assignment")
assertEqual(specialistAssignCalls[1].assignedStationId, "WorkStation_A", "wood station assigned")
assertEqual(
	woodcutter:GetAttribute(TinyfolkJobSchedulingConfig.ScheduledJobKindAttribute),
	TinyfolkJobSchedulingConfig.JobKinds.SpecialistProduction,
	"woodcutter scheduled job kind set"
)
assertEqual(
	hauler:GetAttribute(TinyfolkJobSchedulingConfig.ScheduledJobKindAttribute),
	TinyfolkJobSchedulingConfig.JobKinds.GeneralHaul,
	"hauler scheduled job kind set"
)
assertEqual(
	hauler:GetAttribute(TinyfolkJobSchedulingConfig.ScheduledJobMaterialAttribute),
	"Wood",
	"hauler haul material set"
)

local secondSnapshot = queryApi.ProcessTick()
assertEqual(secondSnapshot.assignmentCount, 0, "second tick does not duplicate assignments")

testHooks.Reset()
_G._TinyfolkJobSchedulingService_DisableAutoStart = nil

print("tinyfolk_job_scheduling_service_runtime_entrypoint: all checks passed")
