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

if Color3 == nil then
	Color3 = {
		fromRGB = function()
			return {}
		end,
	} :: any
end

if Enum == nil then
	Enum = { Material = { Grass = "Grass" } } :: any
end

local function makeSignal()
	local callbacks: { (...any) -> () } = {}
	return {
		Connect = function(_self: any, callback: (...any) -> ())
			table.insert(callbacks, callback)
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

	function node:IsA(expectedClass: string): boolean
		return self.ClassName == expectedClass
	end

	function node:GetFullName(): string
		return self._FullName
	end

	function node:FindFirstChild(childName: string): any
		return self._Children[childName]
	end

	function node:WaitForChild(childName: string, _timeout: number?): any
		return self._Children[childName]
	end

	function node:GetChildren(): { any }
		local children: { any } = {}
		for _, child in pairs(self._Children) do
			table.insert(children, child)
		end
		return children
	end

	function node:GetDescendants(): { any }
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

	function node:SetAttribute(attributeName: string, value: any)
		self._Attributes[attributeName] = value
	end

	function node:GetAttribute(attributeName: string): any
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

	function remote:IsA(expectedClass: string): boolean
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
	local part = makeNode(name, "BasePart")
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
local buildRemote = makeRemoteEvent("ConstructionBuildRequest")
addChild(remotesFolder, "StationActivateRequest", activateRemote)
addChild(remotesFolder, "StationDebugStateRequest", makeRemoteEvent("StationDebugStateRequest"))
addChild(remotesFolder, "StationDebugStateResponse", makeRemoteEvent("StationDebugStateResponse"))
addChild(remotesFolder, "GranaryDeliverRequest", granaryDeliverRemote)
addChild(remotesFolder, "WarehouseDeliverRequest", makeRemoteEvent("WarehouseDeliverRequest"))
addChild(remotesFolder, "WarehousingDebugStateRequest", makeRemoteEvent("WarehousingDebugStateRequest"))
addChild(remotesFolder, "WarehousingDebugStateResponse", makeRemoteEvent("WarehousingDebugStateResponse"))
addChild(remotesFolder, "ConstructionBuildRequest", buildRemote)
addChild(remotesFolder, "ConstructionDebugStateRequest", makeRemoteEvent("ConstructionDebugStateRequest"))
addChild(remotesFolder, "ConstructionDebugStateResponse", makeRemoteEvent("ConstructionDebugStateResponse"))

local configFolder = makeNode("Config")
configFolder._Children["StationConfig"] = "../../ReplicatedStorage/Shared/Config/StationConfig"
configFolder._Children["RoleConfig"] = "../../ReplicatedStorage/Shared/Config/RoleConfig"
configFolder._Children["SpecialistConfig"] = "../../ReplicatedStorage/Shared/Config/SpecialistConfig"
configFolder._Children["ConstructionConfig"] = "../../ReplicatedStorage/Shared/Config/ConstructionConfig"
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
local constructionSitePart = makeBasePart("ConstructionSite_A", 10, 0, 10)
addChild(stationsFolder, "Farm_A", farmPart)
addChild(stationsFolder, "Granary_A", granaryPart)
addChild(mapFolder, "ConstructionSite_A", constructionSitePart)
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

_G._DistrictPlacementService_QueryAPI = {
	GetAllPlacedDistricts = function()
		return {}
	end,
}

local scriptParent = makeNode("Services")
scriptParent._Children["ResourceFlowState"] = "../../ServerScriptService/Services/ResourceFlowState"
script = { Parent = scriptParent } :: any

local RoleConfig = require("../src/ReplicatedStorage/Shared/Config/RoleConfig")
local SpecialistConfig = require("../src/ReplicatedStorage/Shared/Config/SpecialistConfig")
local StationConfig = require("../src/ReplicatedStorage/Shared/Config/StationConfig")
local ConstructionConfig = require("../src/ReplicatedStorage/Shared/Config/ConstructionConfig")
local ResourceFlowState = require("../src/ServerScriptService/Services/ResourceFlowState")

StationConfig.RequestCooldownSeconds = 0
ConstructionConfig.RequestCooldownSeconds = 0

local farmPlayer = makeAlivePlayer(9501, Vector3.new(40, 0, 10))
farmPlayer:SetAttribute("Role", RoleConfig.Roles.Tinyfolk)
farmPlayer:SetAttribute("SpecialistRole", SpecialistConfig.SpecialistRoles.Farmer)
farmPlayer:SetAttribute("SpecialistAssignedStationId", "Farm_A")

local haulPlayer = makeAlivePlayer(9502, Vector3.new(40, 0, 10))
haulPlayer:SetAttribute("Role", RoleConfig.Roles.Tinyfolk)
haulPlayer:SetAttribute("SpecialistRole", SpecialistConfig.SpecialistRoles.None)

local granaryPlayer = makeAlivePlayer(9503, Vector3.new(35, 0, 10))
granaryPlayer:SetAttribute("Role", RoleConfig.Roles.Tinyfolk)

local builder = makeAlivePlayer(9504, Vector3.new(12, 0, 12))
builder:SetAttribute("Role", RoleConfig.Roles.Tinyfolk)

for _, player in ipairs({ farmPlayer, haulPlayer, granaryPlayer, builder }) do
	table.insert(playersList, player)
end

require("../src/ServerScriptService/Services/StationService.server")
require("../src/ServerScriptService/Services/WarehousingService.server")
require("../src/ServerScriptService/Services/ConstructionService.server")

ResourceFlowState.ResetSession("tin_food_construction_spend_runtime_entrypoint")
ResourceFlowState.RefreshDeliveryPoints()

local siteStateById = _G._ConstructionService_SiteState
assertTrue(type(siteStateById) == "table", "construction site state export present")

local foodCost = ConstructionConfig.CostBySiteId.ConstructionSite_A.food

activateRemote:FireServer(farmPlayer, "Farm_A")
runServiceHeartbeat:Fire(StationConfig.GenerationIntervalSeconds)
activateRemote:FireServer(haulPlayer, "Farm_A")
runServiceHeartbeat:Fire(StationConfig.GenerationIntervalSeconds)
activateRemote:FireServer(haulPlayer, "Farm_A")
granaryDeliverRemote:FireServer(granaryPlayer, "Granary_A")
granaryDeliverRemote:FireServer(granaryPlayer, "Granary_A")

local beforeBuild = ResourceFlowState.GetMaterialSnapshot("Food")
assertTrue(beforeBuild.stored >= foodCost, "granary has enough stored food for construction")

buildRemote:FireServer(builder, "ConstructionSite_A")

local afterBuild = ResourceFlowState.GetMaterialSnapshot("Food")
local siteState = siteStateById["ConstructionSite_A"]
assertTrue(siteState.isBuilt, "construction build succeeds with food cost")
assertEqual(afterBuild.stored, beforeBuild.stored - foodCost, "construction spends stored food")
assertEqual(constructionSitePart:GetAttribute("ConstructionCostFood"), foodCost, "construction site exposes food cost")

print("tin_food_construction_spend_runtime_entrypoint.spec.luau: all checks passed")
