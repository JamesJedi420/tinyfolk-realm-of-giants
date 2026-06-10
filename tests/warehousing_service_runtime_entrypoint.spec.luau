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
		local walk: (current: any) -> ()
		walk = function(current: any)
			for _, child in pairs(current._Children) do
				table.insert(descendants, child)
				if type(child._Children) == "table" then
					walk(child)
				end
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
		Connect = function(_signal: any, handler: (any, any) -> ())
			remote._Handler = handler
		end,
	}

	function remote.FireServer(self: any, player: any, payload: any)
		if self._Handler == nil then
			error(string.format("remote %s handler not connected", self.Name))
		end
		self._Handler(player, payload)
	end

	function remote.FireClient(self: any, _player: any, payload: any)
		self._ClientPayload = payload
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
	local humanoid = {
		Health = 100,
	}
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

local remotesFolder = makeNode("Remotes", "Folder", "ReplicatedStorage.Remotes")
local deliverRemote = makeRemoteEvent("WarehouseDeliverRequest")
local granaryDeliverRemote = makeRemoteEvent("GranaryDeliverRequest")
local debugRequestRemote = makeRemoteEvent("WarehousingDebugStateRequest")
local debugResponseRemote = makeRemoteEvent("WarehousingDebugStateResponse")
addChild(remotesFolder, "WarehouseDeliverRequest", deliverRemote)
addChild(remotesFolder, "GranaryDeliverRequest", granaryDeliverRemote)
addChild(remotesFolder, "WarehousingDebugStateRequest", debugRequestRemote)
addChild(remotesFolder, "WarehousingDebugStateResponse", debugResponseRemote)

local configFolder = makeNode("Config", "Folder", "ReplicatedStorage.Shared.Config")
configFolder._Children["StationConfig"] = "../../ReplicatedStorage/Shared/Config/StationConfig"

local sharedFolder = makeNode("Shared", "Folder", "ReplicatedStorage.Shared")
addChild(sharedFolder, "Config", configFolder)

local replicatedStorage = makeNode("ReplicatedStorage", "ReplicatedStorage", "ReplicatedStorage")
addChild(replicatedStorage, "Shared", sharedFolder)
addChild(replicatedStorage, "Remotes", remotesFolder)

local workspaceService = makeNode("Workspace", "Workspace", "Workspace")
local mapFolder = makeNode("Map", "Folder", "Workspace.Map")
local stationsFolder = makeNode("Stations", "Folder", "Workspace.Map.Stations")
addChild(stationsFolder, "Warehouse_A", makeBasePart("Warehouse_A", 30, 0, 10))
addChild(stationsFolder, "Granary_A", makeBasePart("Granary_A", 35, 0, 10))
addChild(mapFolder, "Stations", stationsFolder)
addChild(workspaceService, "Map", mapFolder)

local playersList: { any } = {}
local playerRemoving = makeSignal()
local playersService: any = {
	PlayerRemoving = playerRemoving,
	GetPlayers = function(_self: any)
		return playersList
	end,
}

local fakeGame = {}
function fakeGame:GetService(serviceName: string): any
	if serviceName == "ReplicatedStorage" then
		return replicatedStorage
	end
	if serviceName == "Workspace" then
		return workspaceService
	end
	if serviceName == "Players" then
		return playersService
	end
	error(string.format("unsupported service: %s", serviceName))
	return nil
end

game = fakeGame

local scriptParent = makeNode("Services", "Folder", "ServerScriptService.Services")
scriptParent._Children["ResourceFlowState"] = "../../ServerScriptService/Services/ResourceFlowState"
script = {
	Parent = scriptParent,
} :: any

local StationConfig = require("../src/ReplicatedStorage/Shared/Config/StationConfig")
StationConfig.RequestCooldownSeconds = 0

local ResourceFlowState = require("../src/ServerScriptService/Services/ResourceFlowState")
ResourceFlowState.ResetSession("warehousing_service_runtime_entrypoint")
ResourceFlowState.AddProduced("Wood", "Test:Station", 4)
ResourceFlowState.TransferProducedToInTransit("Wood", 4)

local loaded, loadError = pcall(function()
	require("../src/ServerScriptService/Services/WarehousingService.server")
end)
if not loaded then
	error(string.format("FAIL [warehousing service loads]: %s", tostring(loadError)))
end

assertTrue(deliverRemote._Handler ~= nil, "warehousing service binds WarehouseDeliverRequest handler")
assertTrue(granaryDeliverRemote._Handler ~= nil, "warehousing service binds GranaryDeliverRequest handler")

ResourceFlowState.RefreshDeliveryPoints()

local player = makeAlivePlayer(8101, Vector3.new(30, 0, 10))
table.insert(playersList, player)

local beforeDeliver = ResourceFlowState.GetMaterialSnapshot("Wood")
deliverRemote:FireServer(player, "Warehouse_A")
local afterDeliver = ResourceFlowState.GetMaterialSnapshot("Wood")
assertTrue(afterDeliver.inTransit < beforeDeliver.inTransit, "warehouse delivery reduces Wood in transit")
assertTrue(afterDeliver.stored > beforeDeliver.stored, "warehouse delivery increases stored Wood")
assertEqual(
	beforeDeliver.inTransit - afterDeliver.inTransit,
	StationConfig.HaulTransferPerStepByMaterial.Wood,
	"warehouse delivery moves configured haul step amount"
)
assertEqual(
	stationsFolder._Children["Warehouse_A"]:GetAttribute("WoodStoredTotal"),
	afterDeliver.stored,
	"warehouse attributes update stored Wood"
)

debugRequestRemote:FireServer(player, "Warehouse_A")
local debugPayload = debugResponseRemote._ClientPayload
assertEqual(debugPayload.warehouseId, "Warehouse_A", "warehouse debug returns target id")
assertEqual(debugPayload.woodInTransit, afterDeliver.inTransit, "warehouse debug returns Wood in transit")
assertEqual(debugPayload.woodStored, afterDeliver.stored, "warehouse debug returns stored Wood")

ResourceFlowState.ResetSession("granary_food_delivery_test")
ResourceFlowState.AddProduced("Food", "Farm:Farm_A", 4)
ResourceFlowState.TransferProducedToInTransit("Food", 4)
ResourceFlowState.RefreshDeliveryPoints()

local granaryPlayer = makeAlivePlayer(8102, Vector3.new(35, 0, 10))
table.insert(playersList, granaryPlayer)

local beforeFoodDeliver = ResourceFlowState.GetMaterialSnapshot("Food")
granaryDeliverRemote:FireServer(granaryPlayer, "Granary_A")
local afterFoodDeliver = ResourceFlowState.GetMaterialSnapshot("Food")
assertTrue(afterFoodDeliver.inTransit < beforeFoodDeliver.inTransit, "granary delivery reduces Food in transit")
assertTrue(afterFoodDeliver.stored > beforeFoodDeliver.stored, "granary delivery increases stored Food")
assertEqual(
	beforeFoodDeliver.inTransit - afterFoodDeliver.inTransit,
	StationConfig.HaulTransferPerStepByMaterial.Food,
	"granary delivery moves configured haul step amount"
)
assertEqual(afterFoodDeliver.lastDeliveredTo, StationConfig.DefaultGranaryId, "food delivery routes to granary")
assertEqual(
	stationsFolder._Children["Granary_A"]:GetAttribute("FoodStoredTotal"),
	afterFoodDeliver.stored,
	"granary attributes update stored Food"
)

print("warehousing_service_runtime_entrypoint: all checks passed")
