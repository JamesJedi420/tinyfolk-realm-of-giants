--!nocheck
--!nolint BuiltinGlobalWrite

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(string.format("FAIL [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual)))
	end
end

local function assertTrue(value: boolean, label: string)
	assertEqual(value, true, label)
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
addChild(stationsFolder, "Granary_A", makeBasePart("Granary_A", 35, 0, 10))
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

ResourceFlowState.ResetSession("resource_flow_food_spec")
ResourceFlowState.RefreshDeliveryPoints()

do
	local produced = ResourceFlowState.AddProduced("Food", "Farm:Farm_A", 6)
	assertEqual(produced.produced, 6, "food produced total")
	assertEqual(produced.stored, 0, "food not stored before delivery")
end

do
	local before = ResourceFlowState.GetMaterialSnapshot("Food")
	local afterTransit = ResourceFlowState.TransferProducedToInTransit("Food", 4)
	assertEqual(afterTransit.inTransit, 4, "food moved to in-transit")
	assertEqual(afterTransit.produced, before.produced - 4, "food produced reduced after haul")
end

do
	local before = ResourceFlowState.GetMaterialSnapshot("Food")
	local afterStored = ResourceFlowState.TransferInTransitToStored("Food", 2)
	assertTrue(afterStored.stored > before.stored, "food stored at granary delivery point")
	assertEqual(afterStored.lastDeliveredTo, StationConfig.DefaultGranaryId, "food delivers to granary")
end

print("resource_flow_food.spec.luau: all checks passed")
