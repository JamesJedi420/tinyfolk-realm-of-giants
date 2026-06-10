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
		_AttributeChangedSignals = {},
		SetAttribute = function(self: any, attributeName: string, value: any)
			self._Attributes[attributeName] = value
		end,
		GetAttribute = function(self: any, attributeName: string): any
			return self._Attributes[attributeName]
		end,
		GetAttributeChangedSignal = function(self: any, attributeName: string): any
			local existing = self._AttributeChangedSignals[attributeName]
			if existing == nil then
				existing = makeSignal()
				self._AttributeChangedSignals[attributeName] = existing
			end
			return existing
		end,
	}
end

local remotesFolder = makeNode("Remotes")
local activateRemote = makeRemoteEvent("StationActivateRequest")
local warehouseDeliverRemote = makeRemoteEvent("WarehouseDeliverRequest")
addChild(remotesFolder, "StationActivateRequest", activateRemote)
addChild(remotesFolder, "StationDebugStateRequest", makeRemoteEvent("StationDebugStateRequest"))
addChild(remotesFolder, "StationDebugStateResponse", makeRemoteEvent("StationDebugStateResponse"))
addChild(remotesFolder, "WarehouseDeliverRequest", warehouseDeliverRemote)
addChild(remotesFolder, "GranaryDeliverRequest", makeRemoteEvent("GranaryDeliverRequest"))
addChild(remotesFolder, "WarehousingDebugStateRequest", makeRemoteEvent("WarehousingDebugStateRequest"))
addChild(remotesFolder, "WarehousingDebugStateResponse", makeRemoteEvent("WarehousingDebugStateResponse"))
addChild(remotesFolder, "InventoryCraftDebugStateRequest", makeRemoteEvent("InventoryCraftDebugStateRequest"))
addChild(remotesFolder, "InventoryCraftDebugStateResponse", makeRemoteEvent("InventoryCraftDebugStateResponse"))
addChild(remotesFolder, "InventoryCraftRequest", makeRemoteEvent("InventoryCraftRequest"))

local configFolder = makeNode("Config")
configFolder._Children["StationConfig"] = "../../ReplicatedStorage/Shared/Config/StationConfig"
configFolder._Children["RoleConfig"] = "../../ReplicatedStorage/Shared/Config/RoleConfig"
configFolder._Children["SpecialistConfig"] = "../../ReplicatedStorage/Shared/Config/SpecialistConfig"
configFolder._Children["LaborActionConfig"] = "../../ReplicatedStorage/Shared/Config/LaborActionConfig"
configFolder._Children["InventoryCraftConfig"] = "../../ReplicatedStorage/Shared/Config/InventoryCraftConfig"
configFolder._Children["AdvancedMaterialFlowConfig"] =
	"../../ReplicatedStorage/Shared/Config/AdvancedMaterialFlowConfig"
configFolder._Children["VillageWorksiteUpgradeConfig"] =
	"../../ReplicatedStorage/Shared/Config/VillageWorksiteUpgradeConfig"

local giantRealmFolder = makeNode("GiantRealm")
giantRealmFolder._Children["VillageWorksiteUpgradeState"] =
	"../../ReplicatedStorage/Shared/GiantRealm/VillageWorksiteUpgradeState"
giantRealmFolder._Children["LaborActionState"] = "../../ReplicatedStorage/Shared/GiantRealm/LaborActionState"
giantRealmFolder._Children["AdvancedMaterialFlowState"] =
	"../../ReplicatedStorage/Shared/GiantRealm/AdvancedMaterialFlowState"

local inventoryCraftFolder = makeNode("InventoryCraft")
inventoryCraftFolder._Children["InventoryCraftState"] =
	"../../ReplicatedStorage/Shared/InventoryCraft/InventoryCraftState"

local sharedConstructionFolder = makeNode("Construction")
sharedConstructionFolder._Children["ContextualTaskProgressLogic"] =
	"../../ReplicatedStorage/Shared/Construction/ContextualTaskProgressLogic"
sharedConstructionFolder._Children["TaskQteTimingLogic"] =
	"../../ReplicatedStorage/Shared/Construction/TaskQteTimingLogic"

local sharedFolder = makeNode("Shared")
addChild(sharedFolder, "Config", configFolder)
addChild(sharedFolder, "GiantRealm", giantRealmFolder)
addChild(sharedFolder, "InventoryCraft", inventoryCraftFolder)
addChild(sharedFolder, "Construction", sharedConstructionFolder)

local replicatedStorage = makeNode("ReplicatedStorage")
addChild(replicatedStorage, "Shared", sharedFolder)
addChild(replicatedStorage, "Remotes", remotesFolder)

local workspaceService = makeNode("Workspace")
local mapFolder = makeNode("Map")
local stationsFolder = makeNode("Stations")
local forgePart = makeBasePart("Forge_A", 90, 0, 10)
local warehousePart = makeBasePart("Warehouse_A", 30, 0, 10)
addChild(stationsFolder, "Forge_A", forgePart)
addChild(stationsFolder, "Warehouse_A", warehousePart)
addChild(mapFolder, "Stations", stationsFolder)
addChild(workspaceService, "Map", mapFolder)

local runServiceHeartbeat = makeSignal()
local playersList: { any } = {}
local playerAdded = makeSignal()
local playerRemoving = makeSignal()
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
			PlayerAdded = playerAdded,
			PlayerRemoving = playerRemoving,
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

local forgePlayer = makeAlivePlayer(9301, Vector3.new(90, 0, 10))
forgePlayer:SetAttribute("Role", RoleConfig.Roles.Tinyfolk)
forgePlayer:SetAttribute("SpecialistRole", SpecialistConfig.SpecialistRoles.Miner)
forgePlayer:SetAttribute("SpecialistAssignedStationId", "Forge_A")
table.insert(playersList, forgePlayer)

local haulPlayer = makeAlivePlayer(9302, Vector3.new(90, 0, 10))
haulPlayer:SetAttribute("Role", RoleConfig.Roles.Tinyfolk)
haulPlayer:SetAttribute("SpecialistRole", SpecialistConfig.SpecialistRoles.None)
table.insert(playersList, haulPlayer)

local warehousePlayer = makeAlivePlayer(9303, Vector3.new(30, 0, 10))
warehousePlayer:SetAttribute("Role", RoleConfig.Roles.Tinyfolk)
warehousePlayer:SetAttribute("SpecialistRole", SpecialistConfig.SpecialistRoles.None)
table.insert(playersList, warehousePlayer)

require("../src/ServerScriptService/Services/InventoryCraftService.server")
require("../src/ServerScriptService/Services/StationService.server")
require("../src/ServerScriptService/Services/WarehousingService.server")

ResourceFlowState.ResetSession("tin_metal_forge_warehouse_runtime_entrypoint")
ResourceFlowState.RefreshDeliveryPoints()

local craftApi: any = _G._InventoryCraftService_QueryAPI
local stoneBeforeRefine = ResourceFlowState.GetMaterialSnapshot("Stone").stored
local inventoryBeforeDeliver = craftApi.GetSnapshot(warehousePlayer)
local ironBeforeDeliver = inventoryBeforeDeliver.itemCounts.iron_filings or 0

activateRemote:FireServer(forgePlayer, {
	stationId = "Forge_A",
	mode = "begin",
	now = 0,
})
activateRemote:FireServer(forgePlayer, {
	stationId = "Forge_A",
	mode = "complete",
	now = StationConfig.TaskDurationSeconds + 0.1,
})

local afterRefine = ResourceFlowState.GetMaterialSnapshot("Metal")
assertTrue(afterRefine.produced >= StationConfig.MetalPerTick, "forge refines stored stone into metal produced pool")
assertEqual(
	ResourceFlowState.GetMaterialSnapshot("Stone").stored,
	stoneBeforeRefine - StationConfig.StoneStoredCostPerRefineTick,
	"forge refine spends stored stone"
)

activateRemote:FireServer(haulPlayer, "Forge_A")
local afterHaul = ResourceFlowState.GetMaterialSnapshot("Metal")
assertTrue(afterHaul.inTransit > 0, "haul moves metal to in-transit")

warehouseDeliverRemote:FireServer(warehousePlayer, "Warehouse_A")
local afterDeliver = ResourceFlowState.GetMaterialSnapshot("Metal")
assertTrue(afterDeliver.stored > 0, "warehouse stores delivered metal")
assertEqual(afterDeliver.lastDeliveredTo, StationConfig.DefaultWarehouseId, "metal routes to warehouse")
assertEqual(warehousePart:GetAttribute("MetalStoredTotal"), afterDeliver.stored, "warehouse mirrors stored metal")

local afterInventory = craftApi.GetSnapshot(warehousePlayer)
assertEqual(
	afterInventory.itemCounts.iron_filings,
	ironBeforeDeliver + afterDeliver.lastDeliveredAmount,
	"warehouse metal delivery grants iron_filings to delivering player"
)

print("tin_metal_forge_warehouse_runtime_entrypoint.spec.luau: all checks passed")
