--!nocheck
--!nolint BuiltinGlobalWrite

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(string.format("FAIL [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual)))
	end
end

if Vector3 == nil then
	local vector3Mt: any = {}
	Vector3 = {
		new = function(x: number, y: number, z: number)
			return setmetatable({ X = x, Y = y, Z = z }, vector3Mt)
		end,
	} :: any
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

	return node
end

local function addChild(parent: any, childName: string, child: any)
	parent._Children[childName] = child
	if type(child) == "table" then
		(child :: any).Parent = parent
	end
end

local function makeBasePart(name: string, x: number, y: number, z: number)
	local part = makeNode(name, "BasePart", "Workspace.Map.Stations." .. name)
	part.Position = Vector3.new(x, y, z)
	part._Attributes = {}
	function part.SetAttribute(self: any, attributeName: string, value: any)
		self._Attributes[attributeName] = value
	end
	return part
end

local configFolder = makeNode("Config", "Folder", "ReplicatedStorage.Shared.Config")
configFolder._Children["StationConfig"] = "../../ReplicatedStorage/Shared/Config/StationConfig"

local sharedFolder = makeNode("Shared", "Folder", "ReplicatedStorage.Shared")
addChild(sharedFolder, "Config", configFolder)

local replicatedStorage = makeNode("ReplicatedStorage", "ReplicatedStorage", "ReplicatedStorage")
addChild(replicatedStorage, "Shared", sharedFolder)

local workspaceService = makeNode("Workspace", "Workspace", "Workspace")
local mapFolder = makeNode("Map", "Folder", "Workspace.Map")
local stationsFolder = makeNode("Stations", "Folder", "Workspace.Map.Stations")
addChild(stationsFolder, "Warehouse_A", makeBasePart("Warehouse_A", 30, 0, 10))
addChild(mapFolder, "Stations", stationsFolder)
addChild(workspaceService, "Map", mapFolder)

local fakeGame = {}
function fakeGame:GetService(serviceName: string): any
	if serviceName == "ReplicatedStorage" then
		return replicatedStorage
	end
	if serviceName == "Workspace" then
		return workspaceService
	end
	error(string.format("unsupported service: %s", serviceName))
	return nil
end

game = fakeGame

local StationConfig = require("../src/ReplicatedStorage/Shared/Config/StationConfig")
local ResourceFlowState = require("../src/ServerScriptService/Services/ResourceFlowState")

ResourceFlowState.ResetSession("resource_flow_metal_spec")
ResourceFlowState.RefreshDeliveryPoints()

do
	local produced = ResourceFlowState.AddProduced("Metal", "Forge:Forge_A", 3)
	assertEqual(produced.produced, 3, "metal produced total")
	assertEqual(produced.stored, 0, "metal not stored before delivery")
end

do
	ResourceFlowState.AddProduced("Metal", "Forge:Forge_A", 4)
	local before = ResourceFlowState.GetMaterialSnapshot("Metal")
	local afterTransit = ResourceFlowState.TransferProducedToInTransit("Metal", 2)
	assertEqual(afterTransit.inTransit, before.inTransit + 2, "metal haul to transit")
	assertEqual(afterTransit.produced, before.produced - 2, "metal produced reduced by haul")
end

do
	local before = ResourceFlowState.GetMaterialSnapshot("Metal")
	local afterStored = ResourceFlowState.TransferInTransitToStored("Metal", 2)
	assertEqual(afterStored.stored, before.stored + 2, "metal warehouse delivery stores")
	assertEqual(afterStored.inTransit, before.inTransit - 2, "metal in-transit reduced by delivery")
	assertEqual(afterStored.lastDeliveredTo, StationConfig.DefaultWarehouseId, "metal routes to warehouse")
end

print("resource_flow_metal.spec.luau: all checks passed")
