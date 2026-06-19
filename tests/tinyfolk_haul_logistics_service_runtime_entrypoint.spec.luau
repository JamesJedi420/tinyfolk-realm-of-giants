--!nocheck
--!nolint BuiltinGlobalWrite
-- selene: allow(global_usage)

local StationConfig = require("../src/ReplicatedStorage/Shared/Config/StationConfig")
local TinyfolkHaulLogisticsConfig = require("../src/ReplicatedStorage/Shared/Config/TinyfolkHaulLogisticsConfig")
local TinyfolkJobSchedulingConfig = require("../src/ReplicatedStorage/Shared/Config/TinyfolkJobSchedulingConfig")
local RoleConfig = require("../src/ReplicatedStorage/Shared/Config/RoleConfig")

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(string.format("FAIL [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual)))
	end
	print(string.format("PASS [%s]", label))
end

local function assertTrue(condition: boolean, label: string)
	if not condition then
		error(string.format("FAIL [%s]: expected true, got false", label))
	end
	print(string.format("PASS [%s]", label))
end

local function makeVector3(position: { x: number, y: number, z: number })
	return {
		X = position.x,
		Y = position.y,
		Z = position.z,
	}
end

local function makePlayer(userId: number, position: { x: number, y: number, z: number })
	local attributes: { [string]: any } = {
		Role = RoleConfig.Roles.Tinyfolk,
		[TinyfolkJobSchedulingConfig.ScheduledJobKindAttribute] = TinyfolkJobSchedulingConfig.JobKinds.GeneralHaul,
		[TinyfolkJobSchedulingConfig.ScheduledJobMaterialAttribute] = "Wood",
		[TinyfolkJobSchedulingConfig.ScheduledJobStationIdAttribute] = "WorkStation_A",
	}
	local rootPart = {
		Position = makeVector3(position),
		IsA = function(_self: any, className: string)
			return className == "BasePart"
		end,
	}
	local humanoid = {
		Health = 100,
	}
	local character = {
		FindFirstChild = function(_self: any, childName: string)
			if childName == "HumanoidRootPart" then
				return rootPart
			end
			return nil
		end,
		FindFirstChildOfClass = function(_self: any, className: string)
			if className == "Humanoid" then
				return humanoid
			end
			return nil
		end,
	}
	local player: any = {
		UserId = userId,
		Name = "Player" .. tostring(userId),
		Character = character,
	}

	function player:GetAttribute(name: string): any
		return attributes[name]
	end

	function player:SetAttribute(name: string, value: any)
		attributes[name] = value
	end

	player._Attributes = attributes
	player._RootPart = rootPart
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
		if childName == "CaptureConfig" then
			return "../../ReplicatedStorage/Shared/Config/CaptureConfig"
		end
		if childName == "StationConfig" then
			return "../../ReplicatedStorage/Shared/Config/StationConfig"
		end
		if childName == "TinyfolkHaulLogisticsConfig" then
			return "../../ReplicatedStorage/Shared/Config/TinyfolkHaulLogisticsConfig"
		end
		if childName == "TinyfolkJobSchedulingConfig" then
			return "../../ReplicatedStorage/Shared/Config/TinyfolkJobSchedulingConfig"
		end
		error("missing config child " .. childName)
	end,
}

local giantRealmFolder: any = {
	WaitForChild = function(_self: any, childName: string)
		if childName == "TinyfolkHaulLogisticsState" then
			return "../../ReplicatedStorage/Shared/GiantRealm/TinyfolkHaulLogisticsState"
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

local sourcePosition = { x = 0, y = 0, z = 0 }
local warehousePosition = { x = 10, y = 0, z = 0 }
local farPosition = { x = 100, y = 0, z = 0 }

local haulerAtSource = makePlayer(9201, sourcePosition)
local haulerFar = makePlayer(9202, farPosition)
local playersList = { haulerAtSource, haulerFar }

local flowState = {
	Wood = { produced = 6, inTransit = 0, stored = 0 },
	Stone = { produced = 0, inTransit = 0, stored = 0 },
	Food = { produced = 0, inTransit = 0, stored = 0 },
	Metal = { produced = 0, inTransit = 0, stored = 0 },
}

local clearedJobs: { any } = {}
local pickupCalls: { any } = {}
local deliveryCalls: { any } = {}

_G._TinyfolkHaulLogisticsService_DisableAutoStart = true
_G._TinyfolkHaulLogisticsService_StartConfig = nil

require("../src/ServerScriptService/Services/TinyfolkHaulLogisticsService.server")

local testHooks = _G._TinyfolkHaulLogisticsService_TestHooks
local queryApi = _G._TinyfolkHaulLogisticsService_QueryAPI

testHooks.SetPlayersService({
	GetPlayers = function()
		return playersList
	end,
	PlayerRemoving = {
		Connect = function() end,
	},
})
testHooks.SetFlowSnapshotProvider(function()
	return flowState
end)
testHooks.SetGiantRealmActive(true)
testHooks.SetNowFn(function()
	return 100
end)
testHooks.SetLastHaulRequestAtProvider(function(_userId: number)
	return nil
end)
testHooks.SetLaborUpgradeQueryApi({
	GetHaulYieldMultiplier = function(_userId: number)
		return 1.5
	end,
})
testHooks.SetStationQueryApi({
	GetStationHaulSnapshot = function(stationId: string)
		if stationId ~= "WorkStation_A" then
			return nil
		end
		return {
			stationId = stationId,
			materialType = "Wood",
			position = sourcePosition,
		}
	end,
	ApplyScheduledPickup = function(_player: any, stationId: string, maxAmount: number)
		table.insert(pickupCalls, { stationId = stationId, maxAmount = maxAmount })
		local moved = math.min(maxAmount, flowState.Wood.produced)
		flowState.Wood.produced -= moved
		flowState.Wood.inTransit += moved
		return {
			accepted = true,
			movedAmount = moved,
			material = "Wood",
		}
	end,
})
testHooks.SetWarehousingQueryApi({
	GetDeliverySnapshot = function(material: string)
		if material ~= "Wood" then
			return nil
		end
		return {
			deliveryId = "Warehouse_A",
			material = material,
			position = warehousePosition,
		}
	end,
	ApplyScheduledDelivery = function(_player: any, material: string, maxAmount: number)
		table.insert(deliveryCalls, { material = material, maxAmount = maxAmount })
		local moved = math.min(maxAmount, flowState.Wood.inTransit)
		flowState.Wood.inTransit -= moved
		flowState.Wood.stored += moved
		return {
			accepted = true,
			movedAmount = moved,
			deliveryId = "Warehouse_A",
		}
	end,
})
testHooks.SetJobSchedulingQueryApi({
	ClearScheduledJobForUser = function(userId: number, reason: string)
		table.insert(clearedJobs, { userId = userId, reason = reason })
		local player = if userId == haulerAtSource.UserId then haulerAtSource else haulerFar
		player:SetAttribute(TinyfolkJobSchedulingConfig.ScheduledJobKindAttribute, TinyfolkJobSchedulingConfig.JobKinds.None)
		return true
	end,
})

local pickupSnapshot = queryApi.ProcessTick()
assertEqual(pickupSnapshot.actionCount, 2, "pickup tick processes scheduled workers")
assertEqual(#pickupCalls, 1, "only in-range worker picks up")
assertEqual(pickupCalls[1].maxAmount, 3, "pickup uses haul yield multiplier on base 2")
assertEqual(flowState.Wood.inTransit, 3, "wood moved to in transit")
assertEqual(
	haulerAtSource:GetAttribute(TinyfolkHaulLogisticsConfig.PhaseAttribute),
	TinyfolkHaulLogisticsConfig.Phases.Deliver,
	"phase advances to deliver after pickup"
)

haulerAtSource._RootPart.Position = makeVector3(warehousePosition)
flowState.Wood.produced = 0

local deliverSnapshot = queryApi.ProcessTick()
assertEqual(#deliveryCalls, 1, "delivery applied at warehouse range")
assertEqual(flowState.Wood.inTransit, 1, "one wood remains in transit after first delivery step")
assertEqual(flowState.Wood.stored, 2, "wood stored after first delivery step")
assertEqual(#clearedJobs, 0, "job not cleared until pools empty")

local completeSnapshot = queryApi.ProcessTick()
assertEqual(#deliveryCalls, 2, "second delivery step drains remaining in transit")
assertEqual(flowState.Wood.stored, 3, "wood fully stored after second delivery")
local completionClear = nil
for _, entry in ipairs(clearedJobs) do
	if entry.userId == haulerAtSource.UserId and entry.reason == "haul_logistics_complete" then
		completionClear = entry
		break
	end
end
assertTrue(completionClear ~= nil, "scheduled haul job cleared on completion for hauler")
assertEqual(
	haulerAtSource:GetAttribute(TinyfolkJobSchedulingConfig.ScheduledJobKindAttribute),
	TinyfolkJobSchedulingConfig.JobKinds.None,
	"scheduled job kind cleared"
)
assertTrue(completeSnapshot.actionCount >= 1, "completion tick reports actions")

haulerAtSource:SetAttribute(TinyfolkJobSchedulingConfig.ScheduledJobKindAttribute, TinyfolkJobSchedulingConfig.JobKinds.GeneralHaul)
haulerAtSource:SetAttribute(TinyfolkJobSchedulingConfig.ScheduledJobMaterialAttribute, "Wood")
haulerAtSource:SetAttribute(TinyfolkJobSchedulingConfig.ScheduledJobStationIdAttribute, "WorkStation_A")
haulerAtSource:SetAttribute(StationConfig.HaulInteractionActiveAttribute, true)
flowState.Wood = { produced = 4, inTransit = 0, stored = 3 }
pickupCalls = {}
local deferredSnapshot = queryApi.ProcessTick()
assertEqual(#pickupCalls, 0, "manual haul active defers logistics pickup")
assertTrue(deferredSnapshot.actionCount >= 1, "deferred tick still reports actions")

testHooks.SetGiantRealmActive(false)
local hubSnapshot = queryApi.ProcessTick()
assertEqual(hubSnapshot.lastReason, "hub_or_inactive_giant_realm", "inactive realm no-op")

testHooks.Reset()
_G._TinyfolkHaulLogisticsService_DisableAutoStart = nil

print("tinyfolk_haul_logistics_service_runtime_entrypoint: all checks passed")
