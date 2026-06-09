--!nocheck
--!nolint BuiltinGlobalWrite
-- selene: allow(global_usage)

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

if Vector3 == nil then
	local vector3Mt: any = {}
	vector3Mt.__index = function(self: any, key: string)
		if key == "Magnitude" then
			return math.sqrt((self.X * self.X) + (self.Y * self.Y) + (self.Z * self.Z))
		end
		return nil
	end
	vector3Mt.__sub = function(a: any, b: any)
		return setmetatable({ X = a.X - b.X, Y = a.Y - b.Y, Z = a.Z - b.Z }, vector3Mt)
	end

	Vector3 = {
		new = function(x: number, y: number, z: number)
			return setmetatable({ X = x, Y = y, Z = z }, vector3Mt)
		end,
	} :: any
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

	function node.FindFirstChild(self: any, childName: string): any
		return self._Children[childName]
	end

	function node.WaitForChild(self: any, childName: string, _timeout: number?): any
		return self._Children[childName]
	end

	function node.GetDescendants(self: any): { any }
		local descendants: { any } = {}
		local function walk(current: any)
			for _, child in pairs(current._Children) do
				table.insert(descendants, child)
				walk(child)
			end
		end
		walk(self)
		return descendants
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
	child.Parent = parent
end

local function makeRemoteEvent(remoteName: string)
	local remote: any = {
		Name = remoteName,
		ClassName = "RemoteEvent",
		_Handler = nil,
	}

	function remote.IsA(self: any, expectedClass: string): boolean
		return self.ClassName == expectedClass
	end

	remote.OnServerEvent = {
		Connect = function(_signal: any, handler: (any, any) -> ())
			remote._Handler = handler
		end,
	}

	function remote:FireServer(player: any, payload: any)
		if self._Handler == nil then
			error(string.format("remote %s handler not connected", self.Name))
		end
		self._Handler(player, payload)
	end

	return remote
end

local function makeBasePart(name: string, x: number, y: number, z: number)
	local part = makeNode(name, "BasePart", "Workspace.Map.Stations." .. name)
	part.Position = Vector3.new(x, y, z)
	return part
end

local function makeAlivePlayer(userId: number, position: any)
	local root = makeBasePart("HumanoidRootPart", position.X, position.Y, position.Z)
	local humanoid = { Health = 100 }
	local character = {
		FindFirstChild = function(_self: any, childName: string): any
			if childName == "HumanoidRootPart" then
				return root
			end
			return nil
		end,
		FindFirstChildOfClass = function(_self: any, className: string): any
			if className == "Humanoid" then
				return humanoid
			end
			return nil
		end,
	}

	return {
		UserId = userId,
		Character = character,
		_Attributes = {},
		SetAttribute = function(self: any, attributeName: string, value: any)
			self._Attributes[attributeName] = value
		end,
		GetAttribute = function(self: any, attributeName: string): any
			return self._Attributes[attributeName]
		end,
	}
end

local remotesFolder = makeNode("Remotes")
local activateRemote = makeRemoteEvent("StationActivateRequest")
local granaryDeliverRemote = makeRemoteEvent("GranaryDeliverRequest")
addChild(remotesFolder, "StationActivateRequest", activateRemote)
addChild(remotesFolder, "StationDebugStateRequest", makeRemoteEvent("StationDebugStateRequest"))
addChild(remotesFolder, "StationDebugStateResponse", makeRemoteEvent("StationDebugStateResponse"))
addChild(remotesFolder, "WarehouseDeliverRequest", makeRemoteEvent("WarehouseDeliverRequest"))
addChild(remotesFolder, "GranaryDeliverRequest", granaryDeliverRemote)
addChild(remotesFolder, "WarehousingDebugStateRequest", makeRemoteEvent("WarehousingDebugStateRequest"))
addChild(remotesFolder, "WarehousingDebugStateResponse", makeRemoteEvent("WarehousingDebugStateResponse"))

local configFolder = makeNode("Config")
configFolder._Children["StationConfig"] = "../../ReplicatedStorage/Shared/Config/StationConfig"
configFolder._Children["RoleConfig"] = "../../ReplicatedStorage/Shared/Config/RoleConfig"
configFolder._Children["SpecialistConfig"] = "../../ReplicatedStorage/Shared/Config/SpecialistConfig"
configFolder._Children["VillageWorksiteUpgradeConfig"] =
	"../../ReplicatedStorage/Shared/Config/VillageWorksiteUpgradeConfig"

local giantRealmFolder = makeNode("GiantRealm")
giantRealmFolder._Children["VillageWorksiteUpgradeState"] =
	"../../ReplicatedStorage/Shared/GiantRealm/VillageWorksiteUpgradeState"

local sharedConstructionFolder = makeNode("Construction")
sharedConstructionFolder._Children["ContextualTaskProgressLogic"] =
	"../../ReplicatedStorage/Shared/Construction/ContextualTaskProgressLogic"
sharedConstructionFolder._Children["TaskQteTimingLogic"] =
	"../../ReplicatedStorage/Shared/Construction/TaskQteTimingLogic"

local sharedFolder = makeNode("Shared")
addChild(sharedFolder, "Config", configFolder)
addChild(sharedFolder, "GiantRealm", giantRealmFolder)
addChild(sharedFolder, "Construction", sharedConstructionFolder)

local replicatedStorage = makeNode("ReplicatedStorage")
addChild(replicatedStorage, "Shared", sharedFolder)
addChild(replicatedStorage, "Remotes", remotesFolder)

local workspaceService = makeNode("Workspace")
local mapFolder = makeNode("Map")
local stationsFolder = makeNode("Stations")
local farmPart = makeBasePart("Farm_A", 40, 0, 10)
local granaryPart = makeBasePart("Granary_A", 35, 0, 10)
addChild(stationsFolder, "Farm_A", farmPart)
addChild(stationsFolder, "Granary_A", granaryPart)
addChild(mapFolder, "Stations", stationsFolder)
addChild(workspaceService, "Map", mapFolder)

local runServiceHeartbeat = makeSignal()
local playersList: { any } = {}
local fakeGame = {}
function fakeGame:GetService(serviceName: string): any
	if serviceName == "ReplicatedStorage" then
		return replicatedStorage
	end
	if serviceName == "Workspace" then
		return workspaceService
	end
	if serviceName == "RunService" then
		return { Heartbeat = runServiceHeartbeat }
	end
	if serviceName == "Players" then
		return {
			PlayerAdded = { Connect = function() end },
			PlayerRemoving = { Connect = function() end },
			GetPlayers = function()
				return playersList
			end,
		}
	end
	error(string.format("unsupported service: %s", serviceName))
end

game = fakeGame

local scriptParent = makeNode("Services")
scriptParent._Children["ResourceFlowState"] = "../../ServerScriptService/Services/ResourceFlowState"
script = { Parent = scriptParent } :: any

local RoleConfig = require("../src/ReplicatedStorage/Shared/Config/RoleConfig")
local SpecialistConfig = require("../src/ReplicatedStorage/Shared/Config/SpecialistConfig")
local StationConfig = require("../src/ReplicatedStorage/Shared/Config/StationConfig")
local ResourceFlowState = require("../src/ServerScriptService/Services/ResourceFlowState")

StationConfig.RequestCooldownSeconds = 0

local farmPlayer = makeAlivePlayer(9201, Vector3.new(40, 0, 10))
farmPlayer:SetAttribute("Role", RoleConfig.Roles.Tinyfolk)
farmPlayer:SetAttribute("SpecialistRole", SpecialistConfig.SpecialistRoles.Farmer)
farmPlayer:SetAttribute("SpecialistAssignedStationId", "Farm_A")
table.insert(playersList, farmPlayer)

local haulPlayer = makeAlivePlayer(9202, Vector3.new(40, 0, 10))
haulPlayer:SetAttribute("Role", RoleConfig.Roles.Tinyfolk)
haulPlayer:SetAttribute("SpecialistRole", SpecialistConfig.SpecialistRoles.None)
table.insert(playersList, haulPlayer)

local granaryPlayer = makeAlivePlayer(9203, Vector3.new(35, 0, 10))
granaryPlayer:SetAttribute("Role", RoleConfig.Roles.Tinyfolk)
granaryPlayer:SetAttribute("SpecialistRole", SpecialistConfig.SpecialistRoles.None)
table.insert(playersList, granaryPlayer)

require("../src/ServerScriptService/Services/StationService.server")
require("../src/ServerScriptService/Services/WarehousingService.server")

ResourceFlowState.ResetSession("tin_food_economy_farm_granary_runtime_entrypoint")
ResourceFlowState.RefreshDeliveryPoints()

local stationStateById = _G._StationService_StationState
assertTrue(type(stationStateById) == "table", "station state export present")
assertTrue(granaryDeliverRemote._Handler ~= nil, "granary deliver handler bound")

activateRemote:FireServer(farmPlayer, "Farm_A")
runServiceHeartbeat:Fire(StationConfig.GenerationIntervalSeconds)

local afterProduce = ResourceFlowState.GetMaterialSnapshot("Food")
assertTrue(afterProduce.produced >= StationConfig.FoodPerTick, "farm produces Food at station")
assertEqual(afterProduce.inTransit, 0, "no Food in transit before haul")
assertTrue(farmPart:GetAttribute("FoodProducedTotal") == afterProduce.produced, "farm part mirrors Food produced total")

activateRemote:FireServer(haulPlayer, "Farm_A")
local afterHaul = ResourceFlowState.GetMaterialSnapshot("Food")
assertTrue(afterHaul.inTransit > 0, "haul moves Food to in-transit")
assertTrue(afterHaul.produced < afterProduce.produced, "haul reduces produced Food")

granaryDeliverRemote:FireServer(granaryPlayer, "Granary_A")
local afterDeliver = ResourceFlowState.GetMaterialSnapshot("Food")
assertTrue(afterDeliver.stored > 0, "granary stores delivered Food")
assertTrue(afterDeliver.inTransit < afterHaul.inTransit, "granary delivery clears in-transit Food")
assertEqual(afterDeliver.lastDeliveredTo, StationConfig.DefaultGranaryId, "Food routes to Granary_A")
assertEqual(granaryPart:GetAttribute("FoodStoredTotal"), afterDeliver.stored, "granary part mirrors stored Food")
assertEqual(afterDeliver.usable, afterDeliver.stored, "stored Food is usable total")

print("tin_food_economy_farm_granary_runtime_entrypoint.spec.luau: all checks passed")
