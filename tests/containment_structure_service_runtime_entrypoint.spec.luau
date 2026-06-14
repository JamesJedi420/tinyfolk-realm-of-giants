--!nocheck
--!nolint BuiltinGlobalWrite
-- selene: allow(global_usage)

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(string.format("FAIL [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual)))
	end
	print(string.format("PASS [%s]", label))
end

local function assertTrue(condition: boolean, label: string)
	assertEqual(condition, true, label)
end

local function assertFalse(condition: boolean, label: string)
	assertEqual(condition, false, label)
end

local function makeNode(name: string, className: string?)
	local node: any = {
		Name = name,
		ClassName = className or "Folder",
		_Children = {},
	}
	function node:IsA(expectedClass: string): boolean
		return self.ClassName == expectedClass
	end
	function node:FindFirstChild(childName: string): any
		return self._Children[childName]
	end
	function node:WaitForChild(childName: string): any
		return self._Children[childName]
	end
	function node:GetDescendants(): { any }
		local descendants = {}
		for _, child in pairs(self._Children) do
			table.insert(descendants, child)
			if type(child.GetDescendants) == "function" then
				for _, descendant in ipairs(child:GetDescendants()) do
					table.insert(descendants, descendant)
				end
			end
		end
		return descendants
	end
	return node
end

local function addChild(parent: any, childName: string, child: any)
	parent._Children[childName] = child
	if type(child) == "table" then
		child.Parent = parent
	end
end

local function makePart(name: string, position: any, size: any?, attributes: any?): any
	local part = makeNode(name, "BasePart")
	part.Position = position
	part.Size = size or { x = 4, y = 4, z = 4 }
	part._Attributes = attributes or {}
	function part:GetAttribute(attributeName: string): any
		return self._Attributes[attributeName]
	end
	function part:SetAttribute(attributeName: string, value: any)
		self._Attributes[attributeName] = value
	end
	return part
end

local configFolder = makeNode("Config")
addChild(configFolder, "ContainmentStructureConfig", "../../ReplicatedStorage/Shared/Config/ContainmentStructureConfig")
addChild(configFolder, "RoleConfig", "../../ReplicatedStorage/Shared/Config/RoleConfig")

local giantRealmFolder = makeNode("GiantRealm")
addChild(
	giantRealmFolder,
	"ContainmentStructureState",
	"../../ReplicatedStorage/Shared/GiantRealm/ContainmentStructureState"
)

local sharedFolder = makeNode("Shared")
addChild(sharedFolder, "Config", configFolder)
addChild(sharedFolder, "GiantRealm", giantRealmFolder)

local replicatedStorage = makeNode("ReplicatedStorage", "ReplicatedStorage")
addChild(replicatedStorage, "Shared", sharedFolder)

local structurePart = makePart("ContainmentStructure_A", { x = 55, y = 2, z = -88 }, { x = 12, y = 4, z = 10 }, {
	ContainmentStructureType = "cage",
	ContainmentStructureZoneId = "ContainmentStructureZone_A",
	ContainmentStructureCapacity = 2,
	ContainmentStructureEnabled = true,
	ContainmentEscapeInteractionEnabled = true,
})
local zonePart = makePart("ContainmentStructureZone_A", { x = 55, y = 3, z = -82 }, { x = 38, y = 6, z = 22 })

local structuresRoot = makeNode("ContainmentStructures")
addChild(structuresRoot, "ContainmentStructure_A", structurePart)
local zonesRoot = makeNode("ContainmentStructureZones")
addChild(zonesRoot, "ContainmentStructureZone_A", zonePart)
local mapFolder = makeNode("Map")
addChild(mapFolder, "ContainmentStructures", structuresRoot)
addChild(mapFolder, "ContainmentStructureZones", zonesRoot)
local workspaceService = makeNode("Workspace", "Workspace")
addChild(workspaceService, "Map", mapFolder)

local fakeGame: any = {}
function fakeGame:GetService(serviceName: string): any
	if serviceName == "ReplicatedStorage" then
		return replicatedStorage
	end
	if serviceName == "Workspace" then
		return workspaceService
	end
	return {
		GetPlayers = function()
			return {}
		end,
	}
end

game = fakeGame

local ContainmentStructureService =
	require("../src/ServerScriptService/Services/ContainmentStructureService.server")(fakeGame, {
		disableScheduling = true,
	})

do
	assertEqual(ContainmentStructureService.getRegisteredStructureCount(), 1, "registers authored structure")
	local snapshot = ContainmentStructureService.getStructureSnapshot("ContainmentStructure_A")
	assertEqual(snapshot.structureType, "cage", "structure type resolves")
	assertEqual(snapshot.capacity, 2, "structure capacity resolves")
	assertEqual(snapshot.status, "Ready", "ready structure status")
end

do
	local assign = ContainmentStructureService.resolveAssignOccupantForCapture({
		targetUserId = 4201,
		custodianPosition = { x = 55, y = 2, z = -85 },
		targetPosition = { x = 55, y = 2, z = -87 },
	})
	assertTrue(assign.accepted, "assign occupant accepts in zone")
	assertEqual(assign.structureId, "ContainmentStructure_A", "assign picks authored structure")
	local occupied = ContainmentStructureService.getStructureSnapshot("ContainmentStructure_A")
	assertEqual(occupied.occupantCount, 1, "occupant count after assign")
	assertEqual(occupied.status, "Occupied", "occupied status")
end

do
	local outOfRange = ContainmentStructureService.resolveAssignOccupantForCapture({
		targetUserId = 4202,
		custodianPosition = { x = 0, y = 0, z = 0 },
		targetPosition = { x = 1, y = 0, z = 1 },
	})
	assertFalse(outOfRange.accepted, "out-of-range assign rejects")
	assertEqual(outOfRange.reason, "containment_structure_not_in_range", "out-of-range reason")
end

do
	ContainmentStructureService.ResetForTests()
	ContainmentStructureService.resolveAssignOccupantForCapture({
		targetUserId = 4203,
		custodianPosition = { x = 55, y = 2, z = -85 },
		targetPosition = { x = 55, y = 2, z = -87 },
	})
	ContainmentStructureService.resolveAssignOccupantForCapture({
		targetUserId = 4204,
		custodianPosition = { x = 55, y = 2, z = -85 },
		targetPosition = { x = 55, y = 2, z = -87 },
	})
	local full = ContainmentStructureService.resolveAssignOccupantForCapture({
		targetUserId = 4205,
		custodianPosition = { x = 55, y = 2, z = -85 },
		targetPosition = { x = 55, y = 2, z = -87 },
	})
	assertFalse(full.accepted, "capacity full rejects additional assign")
	assertEqual(full.reason, "structure_capacity_full", "capacity full reason")
end

do
	ContainmentStructureService.ResetForTests()
	ContainmentStructureService.resolveAssignOccupantForCapture({
		targetUserId = 9002,
		custodianPosition = { x = 55, y = 2, z = -85 },
		targetPosition = { x = 55, y = 2, z = -87 },
	})
	assertEqual(
		ContainmentStructureService.getStructureIdForTargetUserId(9002),
		"ContainmentStructure_A",
		"lookup structure by occupant"
	)
	local rescue = ContainmentStructureService.canRescueOccupant(9001, 9002, { x = 55, y = 2, z = -84 })
	assertTrue(rescue.accepted, "rescuer in zone can rescue occupant")
	assertTrue(ContainmentStructureService.hasEscapeInteractionForTarget(9002), "occupant has escape interaction")
	local removed = ContainmentStructureService.removeOccupantByTargetUserId(9002)
	assertTrue(removed.accepted, "remove occupant accepts")
	assertEqual(ContainmentStructureService.getStructureIdForTargetUserId(9002), nil, "occupant cleared after remove")
end

print("containment_structure_service_runtime_entrypoint: all checks passed")
